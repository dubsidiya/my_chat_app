// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:convert';

Future<bool> downloadTextFile({
  required String filename,
  required String content,
  String mimeType = 'text/plain; charset=utf-8',
}) async {
  final bytes = Uint8List.fromList(utf8.encode(content));
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return true;
}

