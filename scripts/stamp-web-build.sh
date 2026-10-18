#!/bin/bash
# Проставляет сборке уникальный адрес, чтобы браузер не держал прошлый main.dart.js.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB_DIR="${1:-$ROOT/build/web}"
BUILD_ID="${2:-}"

if [ ! -f "$WEB_DIR/index.html" ]; then
  echo "нет $WEB_DIR/index.html" >&2
  exit 1
fi
if [ ! -f "$WEB_DIR/flutter_bootstrap.js" ]; then
  echo "нет $WEB_DIR/flutter_bootstrap.js" >&2
  exit 1
fi

if [ -z "$BUILD_ID" ]; then
  SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo local)"
  STAMP="$(date -u +%Y%m%d%H%M%S)"
  BUILD_ID="${SHA}${STAMP}"
fi
BUILD_ID="$(printf '%s' "$BUILD_ID" | tr -cd 'A-Za-z0-9')"
if [ -z "$BUILD_ID" ]; then
  echo "пустой build id" >&2
  exit 1
fi

export STAMP_WEB_DIR="$WEB_DIR"
export STAMP_BUILD_ID="$BUILD_ID"

python3 - <<'PY'
import json
import os
import re
from pathlib import Path

web_dir = Path(os.environ["STAMP_WEB_DIR"])
build_id = os.environ["STAMP_BUILD_ID"]

unregister = """  <script>
    (function () {
      try {
        if ('serviceWorker' in navigator) {
          navigator.serviceWorker.getRegistrations().then(function (regs) {
            regs.forEach(function (reg) { reg.unregister(); });
          });
        }
        if (window.caches && caches.keys) {
          caches.keys().then(function (keys) {
            keys.forEach(function (key) { caches.delete(key); });
          });
        }
      } catch (e) {}
    })();
  </script>
"""

index_path = web_dir / "index.html"
index = index_path.read_text()
if "FLUTTER_BUILD_ID" in index:
    index = index.replace("FLUTTER_BUILD_ID", build_id)
else:
    index, count = re.subn(
        r"flutter_bootstrap\.js(?:\?v=[^\"']*)?",
        f"flutter_bootstrap.js?v={build_id}",
        index,
        count=1,
    )
    if count == 0:
        raise SystemExit("index.html не содержит flutter_bootstrap.js")
if "serviceWorker.getRegistrations" not in index:
    index = index.replace("<body>", "<body>\n" + unregister, 1)
index_path.write_text(index)

bootstrap_path = web_dir / "flutter_bootstrap.js"
bootstrap = bootstrap_path.read_text()
bootstrap = re.sub(
    r"main\.dart\.js(?:\?v=[A-Za-z0-9]*)?",
    f"main.dart.js?v={build_id}",
    bootstrap,
)
bootstrap = re.sub(
    r'serviceWorkerVersion:\s*"[^"]*"',
    f'serviceWorkerVersion: "{build_id}"',
    bootstrap,
)
bootstrap_path.write_text(bootstrap)

killer = """/* Сбрасывает кеш старого Flutter service worker и снимает регистрацию. */
self.addEventListener('install', function (event) {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', function (event) {
  event.waitUntil((async function () {
    var keys = await caches.keys();
    await Promise.all(keys.map(function (key) { return caches.delete(key); }));
    await self.clients.claim();
    var windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    await Promise.all(windows.map(function (client) {
      var url = new URL(client.url);
      if (url.searchParams.get('fresh') === '1') return null;
      url.searchParams.set('fresh', '1');
      return client.navigate(url.toString());
    }));
    await self.registration.unregister();
  })());
});

self.addEventListener('fetch', function (event) {
  event.respondWith(fetch(event.request));
});
"""
(web_dir / "flutter_service_worker.js").write_text(killer)

version_path = web_dir / "version.json"
if version_path.exists():
    try:
        data = json.loads(version_path.read_text())
    except json.JSONDecodeError:
        data = {}
    if not isinstance(data, dict):
        data = {}
else:
    data = {}
data["build_id"] = build_id
version_path.write_text(json.dumps(data, indent=2) + "\n")
print(f"web build stamped: {build_id}")
PY
