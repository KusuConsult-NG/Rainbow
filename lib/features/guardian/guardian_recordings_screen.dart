import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rainbow_app/core/guardian/hausa_prompts.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/shared/localization/translations.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';

/// Collects Hausa recordings for a Hausa Guardian model (phase 3).
///
/// For native Hausa speakers who choose to help. Every recording stays on
/// this phone until the person presses Share and picks where to send it;
/// nothing is uploaded by the app. The files come out as 16 kHz WAV with a
/// labels.csv that tool/guardian_eval.dart reads as it is.
class GuardianRecordingsScreen extends ConsumerStatefulWidget {
  const GuardianRecordingsScreen({super.key});

  @override
  ConsumerState<GuardianRecordingsScreen> createState() => _GuardianRecordingsScreenState();
}

class _GuardianRecordingsScreenState extends ConsumerState<GuardianRecordingsScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _agreed = false;
  String? _recordingId;
  Directory? _dir;
  final Map<String, String> _done = {}; // prompt id -> file name
  String? _message;

  String _t(String key) => Translations.get(key, ref.read(languageProvider));

  @override
  void dispose() {
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/guardian_recordings');
    await dir.create(recursive: true);
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      final p = hausaPrompts.where((p) => name.startsWith('${p.id}_')).firstOrNull;
      if (p != null) _done[p.id] = name;
    }
    return _dir = dir;
  }

  Future<void> _toggle(RecordingPrompt p) async {
    if (_recordingId == p.id) {
      await _recorder.stop();
      setState(() => _recordingId = null);
      return;
    }
    if (_recordingId != null) await _recorder.stop();
    if (!(await Permission.microphone.request()).isGranted) {
      setState(() => _message = _t('guardian_problem_mic'));
      return;
    }
    final dir = await _folder();
    final name = '${p.id}_${DateTime.now().millisecondsSinceEpoch}.wav';
    final old = _done[p.id];
    if (old != null) {
      final f = File('${dir.path}/$old');
      if (f.existsSync()) f.deleteSync();
    }
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: '${dir.path}/$name',
    );
    setState(() {
      _recordingId = p.id;
      _done[p.id] = name;
      _message = null;
    });
  }

  Future<void> _share() async {
    if (_recordingId != null) {
      await _recorder.stop();
      setState(() => _recordingId = null);
    }
    final dir = await _folder();
    final rows = [
      for (final p in hausaPrompts)
        if (_done[p.id] != null && File('${dir.path}/${_done[p.id]}').existsSync()) (_done[p.id]!, p),
    ];
    if (rows.isEmpty) {
      setState(() => _message = _t('guardian_rec_none_yet'));
      return;
    }
    final labels = File('${dir.path}/labels.csv');
    await labels.writeAsString(recordingLabelsCsv(rows));
    await SharePlus.instance.share(ShareParams(
      title: _t('guardian_rec_title'),
      files: [for (final (f, _) in rows) XFile('${dir.path}/$f'), XFile(labels.path)],
    ));
  }

  Future<void> _deleteAll() async {
    if (_recordingId != null) await _recorder.stop();
    final dir = await _folder();
    if (dir.existsSync()) await dir.delete(recursive: true);
    setState(() {
      _dir = null;
      _done.clear();
      _recordingId = null;
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(languageProvider);
    final body = GoogleFonts.inter(fontSize: 14, height: 1.4, color: AppColors.onBackground);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: RainbowAppBar(title: _t('guardian_rec_title'), showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: !_agreed
            ? [
                Text(_t('guardian_rec_consent'), style: body),
                const SizedBox(height: 20),
                FilledButton(
                  key: const ValueKey('guardian_rec_accept'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () async {
                    await _folder();
                    setState(() => _agreed = true);
                  },
                  child: Text(_t('guardian_rec_accept')),
                ),
              ]
            : [
                if (_message != null) ...[
                  Text(_message!, style: body.copyWith(color: AppColors.emergency)),
                  const SizedBox(height: 12),
                ],
                for (final p in hausaPrompts) _promptTile(p, body),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey('guardian_rec_share'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _share,
                  icon: const Icon(Icons.ios_share),
                  label: Text('${_t('guardian_rec_share')} (${_done.length})'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const ValueKey('guardian_rec_delete'),
                  onPressed: _done.isEmpty ? null : _deleteAll,
                  child: Text(_t('guardian_rec_delete')),
                ),
              ],
      ),
    );
  }

  Widget _promptTile(RecordingPrompt p, TextStyle body) {
    final recording = _recordingId == p.id;
    final done = _done.containsKey(p.id) && !recording;
    return Card(
      color: AppColors.surfaceContainer,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.hausa, style: body.copyWith(fontWeight: FontWeight.w600, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(p.english, style: body.copyWith(color: AppColors.textDim, fontSize: 12)),
                  if (done) ...[
                    const SizedBox(height: 4),
                    Text(_t('guardian_rec_done'), style: body.copyWith(color: AppColors.success, fontSize: 12)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: ValueKey('guardian_rec_${p.id}'),
              style: FilledButton.styleFrom(
                backgroundColor: recording ? AppColors.emergency : AppColors.primary,
              ),
              onPressed: () => _toggle(p),
              child: Text(_t(recording ? 'guardian_rec_stop' : 'guardian_rec_record')),
            ),
          ],
        ),
      ),
    );
  }
}
