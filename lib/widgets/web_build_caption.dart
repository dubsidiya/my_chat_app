import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../utils/web_build_id.dart'
    if (dart.library.js_interop) '../utils/web_build_id_web.dart';

/// Подпись «Версия 1.0.0+6 / сборка …» только в веб-версии.
class WebBuildCaption extends StatelessWidget {
  const WebBuildCaption({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    final color = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final text = webBuildCaption(
          version: info?.version ?? '',
          buildNumber: info?.buildNumber ?? '',
          buildId: readWebBuildId(),
        );
        if (text.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
          child: SelectableText(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.4, color: color),
          ),
        );
      },
    );
  }
}

/// Текст подписи. Пустые части пропускаются.
String webBuildCaption({
  required String version,
  required String buildNumber,
  String? buildId,
}) {
  final versionText = _versionText(version, buildNumber);
  final buildText = formatWebBuildId(buildId);
  return [
    if (versionText != null) versionText,
    if (buildText != null) buildText,
  ].join('\n');
}

String? formatWebBuildId(String? raw) {
  final id = raw?.trim() ?? '';
  if (id.isEmpty || id == 'FLUTTER_BUILD_ID') return null;
  final match = RegExp(r'^(.*?)(\d{14})$').firstMatch(id);
  if (match == null) return 'Сборка $id';
  final sha = match.group(1)!;
  final ts = match.group(2)!;
  final when =
      '${ts.substring(6, 8)}.${ts.substring(4, 6)}.${ts.substring(0, 4)} '
      '${ts.substring(8, 10)}:${ts.substring(10, 12)} UTC';
  if (sha.isEmpty) return 'Сборка $when';
  return 'Сборка $when · $sha';
}

String? _versionText(String version, String buildNumber) {
  final v = version.trim();
  final b = buildNumber.trim();
  if (v.isEmpty && b.isEmpty) return null;
  if (v.isEmpty) return 'Версия $b';
  if (b.isEmpty) return 'Версия $v';
  return 'Версия $v+$b';
}
