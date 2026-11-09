import 'package:flutter/material.dart';

//owns its controller so it isn't disposed during the close animation
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  String? initial,
  String? hint,
  String? helper,
  String confirm = 'Save',
  TextCapitalization capitalization = TextCapitalization.sentences,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(
      title: title,
      initial: initial,
      hint: hint,
      helper: helper,
      confirm: confirm,
      capitalization: capitalization,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.helper,
    required this.confirm,
    required this.capitalization,
  });

  final String title;
  final String? initial;
  final String? hint;
  final String? helper;
  final String confirm;
  final TextCapitalization capitalization;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: widget.capitalization,
        decoration: InputDecoration(
          hintText: widget.hint,
          helperText: widget.helper,
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}
