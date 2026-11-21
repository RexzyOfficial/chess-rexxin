import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../analysis/game_line.dart';
import '../ui_colors.dart';
import 'review_screen.dart';

class PgnScreen extends StatefulWidget {
  const PgnScreen({super.key});

  @override
  State<PgnScreen> createState() => _PgnScreenState();
}

class _PgnScreenState extends State<PgnScreen> {
  final TextEditingController _text = TextEditingController();
  String? _error;
  String? _fileName;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() => _error = null);
    try {
      final PlatformFile? file = await FilePicker.pickFile();
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final String content = utf8.decode(bytes, allowMalformed: true);
      if (!mounted) return;
      setState(() {
        _text.text = content;
        _fileName = file.name;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Gagal membaca file: $e');
    }
  }

  void _load() {
    FocusScope.of(context).unfocus();
    try {
      final GameLine line = lineFromPgn(_text.text);
      setState(() => _error = null);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReviewScreen(
            line: line,
            title: 'Analyze PGN',
            showArrows: true,
            autoStart: false,
          ),
        ),
      );
    } on GameLineException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'PGN tidak dapat diproses.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 44,
        title: const Text(
          'Analyze PGN',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Upload .pgn'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => setState(() {
                    _text.clear();
                    _fileName = null;
                    _error = null;
                  }),
                  child: const Text('Clear'),
                ),
              ],
            ),
            if (_fileName != null) ...[
              const SizedBox(height: 8),
              Text(
                'File: $_fileName',
                style: const TextStyle(fontSize: 12.5, color: Colors.white60),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              minLines: 8,
              maxLines: 12,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Tempel teks PGN di sini…',
                filled: true,
                fillColor: kPanel,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kPanelBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kPanelBorder),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(fontSize: 13.5, color: Color(0xFFFF8A80)),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _load,
              style: FilledButton.styleFrom(
                backgroundColor: kAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Load PGN'),
            ),
          ],
        ),
      ),
    );
  }
}
