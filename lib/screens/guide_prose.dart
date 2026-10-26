import 'package:flutter/material.dart';

/// Parte un texto guardado en párrafos, sin cambiar sus palabras.
List<String> guideParagraphs(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  final explicit = trimmed
      .split(RegExp(r'\n\s*\n'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (explicit.length > 1) return explicit;
  final sentences = trimmed
      .split(RegExp(r'(?<=\.)\s+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (sentences.length <= 2) return [trimmed];
  final paragraphs = <String>[];
  for (var index = 0; index < sentences.length; index += 2) {
    final end = index + 2 > sentences.length ? sentences.length : index + 2;
    paragraphs.add(sentences.sublist(index, end).join(' '));
  }
  return paragraphs;
}

class GuideProse extends StatelessWidget {
  final String text;
  final TextStyle style;

  const GuideProse({super.key, required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    final paragraphs = guideParagraphs(text);
    if (paragraphs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final paragraph in paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(paragraph, style: style),
          ),
      ],
    );
  }
}
