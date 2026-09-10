import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

const _rootId = 'reollity-native-send';

JSFunction? _onClick;
JSFunction? _onKeyDown;

/// Поле и кнопка в обычном HTML поверх Flutter-canvas.
/// Клик и Enter не проходят через TextField/оверлей — fetch идёт из браузера.
void mountWebNativeSend({
  required String apiBase,
  required String chatId,
  required Future<String?> Function() getToken,
  required void Function(String text, Map<String, dynamic>? json) onSent,
  required void Function(String message) onError,
}) {
  unmountWebNativeSend();

  final root = web.document.createElement('div') as web.HTMLDivElement;
  root.id = _rootId;
  root.setAttribute(
    'style',
    'position:fixed;left:0;right:0;bottom:0;z-index:2147483647;'
    'display:flex;align-items:flex-end;gap:8px;'
    'padding:10px 12px calc(10px + env(safe-area-inset-bottom, 0px));'
    'box-sizing:border-box;'
    'background:rgba(16,16,22,0.97);'
    'border-top:1px solid rgba(255,255,255,0.12);'
    'font-family:system-ui,sans-serif;',
  );

  final ta = web.document.createElement('textarea') as web.HTMLTextAreaElement;
  ta.id = '$_rootId-text';
  ta.rows = 2;
  ta.placeholder = 'Сообщение';
  ta.setAttribute(
    'style',
    'flex:1;min-height:44px;max-height:120px;resize:none;'
    'border-radius:22px;border:1px solid rgba(255,255,255,0.22);'
    'padding:10px 14px;background:rgba(255,255,255,0.08);'
    'color:#fff;font-size:16px;line-height:20px;outline:none;',
  );

  final btn = web.document.createElement('button') as web.HTMLButtonElement;
  btn.type = 'button';
  btn.id = '$_rootId-btn';
  btn.textContent = '➤';
  btn.title = 'Отправить';
  btn.setAttribute(
    'style',
    'width:48px;height:48px;flex:0 0 48px;border:none;border-radius:50%;'
    'background:linear-gradient(135deg,#7c5cff,#3ec7ff);color:#fff;'
    'font-size:18px;cursor:pointer;',
  );

  var sending = false;

  Future<void> send() async {
    if (sending) return;
    final text = ta.value.trim();
    if (text.isEmpty) {
      onError('Введите текст сообщения');
      return;
    }
    sending = true;
    btn.disabled = true;
    btn.textContent = '…';
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        onError('Нет сессии. Войдите снова.');
        return;
      }
      final headers = web.Headers();
      headers.set('Content-Type', 'application/json');
      headers.set('Authorization', 'Bearer $token');
      headers.set(
        'Idempotency-Key',
        'web-$chatId-${DateTime.now().microsecondsSinceEpoch}',
      );
      final resp = await web.window
          .fetch(
            '$apiBase/messages'.toJS,
            web.RequestInit(
              method: 'POST',
              headers: headers,
              body: jsonEncode({
                'chat_id': chatId,
                'content': text,
              }).toJS,
            ),
          )
          .toDart;
      final raw = (await resp.text().toDart).toDart;
      if (resp.status != 201) {
        var msg = 'Ошибка отправки (${resp.status})';
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map && decoded['message'] != null) {
            msg = decoded['message'].toString();
          }
        } catch (_) {
          if (raw.trim().isNotEmpty) msg = raw;
        }
        onError(msg);
        return;
      }
      ta.value = '';
      Map<String, dynamic>? json;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) json = decoded;
        if (decoded is Map) json = Map<String, dynamic>.from(decoded);
      } catch (_) {}
      onSent(text, json);
    } catch (e) {
      onError('Сеть: $e');
    } finally {
      sending = false;
      btn.disabled = false;
      btn.textContent = '➤';
    }
  }

  _onClick = ((web.Event event) {
    event.preventDefault();
    event.stopPropagation();
    unawaited(send());
  }).toJS;
  _onKeyDown = ((web.Event event) {
    final ke = event as web.KeyboardEvent;
    final isEnter =
        ke.key == 'Enter' || ke.code == 'Enter' || ke.code == 'NumpadEnter';
    if (!isEnter || ke.shiftKey || ke.isComposing) return;
    ke.preventDefault();
    ke.stopPropagation();
    unawaited(send());
  }).toJS;

  btn.addEventListener('click', _onClick!);
  ta.addEventListener('keydown', _onKeyDown!);
  root.appendChild(ta);
  root.appendChild(btn);
  web.document.body?.appendChild(root);
}

void unmountWebNativeSend() {
  final existing = web.document.getElementById(_rootId);
  if (existing != null) {
    existing.remove();
  }
  _onClick = null;
  _onKeyDown = null;
}
