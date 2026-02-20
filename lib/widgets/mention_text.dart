import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class MentionText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final TextStyle mentionStyle;
  final void Function(String handle)? onMentionTap;

  const MentionText({
    super.key,
    required this.text,
    required this.style,
    required this.mentionStyle,
    this.onMentionTap,
  });

  @override
  State<MentionText> createState() => _MentionTextState();
}

class _MentionTextState extends State<MentionText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final spans = <InlineSpan>[];
    final text = widget.text;
    final re = RegExp(r'@([a-zA-Z0-9._-]{1,50})');
    int last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: widget.style));
      }
      final handle = (m.group(1) ?? '').trim();
      final mentionText = text.substring(m.start, m.end);
      final rec = TapGestureRecognizer()
        ..onTap = () {
          if (handle.isEmpty) return;
          widget.onMentionTap?.call(handle);
        };
      _recognizers.add(rec);
      spans.add(TextSpan(text: mentionText, style: widget.mentionStyle, recognizer: rec));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: widget.style));
    }

    return RichText(
      text: TextSpan(children: spans),
      textAlign: TextAlign.start,
      softWrap: true,
    );
  }
}

