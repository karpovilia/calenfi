import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Текст с кликабельными ссылками (http/https). Рекогнайзеры освобождаются
/// в dispose, чтобы не текли.
class LinkifiedText extends StatefulWidget {
  const LinkifiedText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final _recognizers = <TapGestureRecognizer>[];
  static final _urlRe = RegExp(r'(https?://[^\s]+)');

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = widget.style ?? const TextStyle(color: Colors.grey);
    final linkStyle = TextStyle(
      color: Colors.lightBlueAccent,
      decoration: TextDecoration.underline,
    );

    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _urlRe.allMatches(widget.text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: widget.text.substring(last, m.start)));
      }
      final url = m.group(0)!;
      final rec = TapGestureRecognizer()..onTap = () => _open(url);
      _recognizers.add(rec);
      spans.add(TextSpan(text: url, style: linkStyle, recognizer: rec));
      last = m.end;
    }
    if (last < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(last)));
    }

    return SelectableText.rich(TextSpan(style: baseStyle, children: spans));
  }

  static Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
