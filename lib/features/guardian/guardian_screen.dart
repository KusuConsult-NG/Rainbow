import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/guardian/distress_detector.dart';
import 'package:rainbow_app/core/guardian/guardian_provider.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/shared/localization/translations.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';

/// Switches AI Emergency Guardian on and off, and sets the secret phrase.
///
/// The notice comes first: until the user has read what Guardian listens for,
/// what it sends and where it does not work, nothing else is offered.
class GuardianScreen extends ConsumerStatefulWidget {
  const GuardianScreen({super.key});

  @override
  ConsumerState<GuardianScreen> createState() => _GuardianScreenState();
}

class _GuardianScreenState extends ConsumerState<GuardianScreen> {
  final TextEditingController _phrase = TextEditingController();
  Duration _length = guardianDurations.first;
  String? _phraseMessage;
  bool _phraseMessageIsError = false;
  bool _starting = false;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Repaints the "listening until" line; cheap, and only while open.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _phrase.dispose();
    super.dispose();
  }

  String _t(String key) => Translations.get(key, ref.read(languageProvider));

  @override
  Widget build(BuildContext context) {
    ref.watch(languageProvider);
    final consented = ref.watch(guardianConsentProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: RainbowAppBar(title: _t('guardian_title'), showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: consented ? _controls() : _notice(),
      ),
    );
  }

  TextStyle get _body => GoogleFonts.inter(fontSize: 14, height: 1.4, color: AppColors.onBackground);
  TextStyle get _heading =>
      GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.onBackground);

  List<Widget> _notice() => [
        Text(_t('guardian_consent_heading'), style: _heading),
        const SizedBox(height: 12),
        for (final key in const [
          'guardian_consent_listens',
          'guardian_consent_sends',
          'guardian_consent_private',
          'guardian_consent_limits',
        ]) ...[
          Text(_t(key), style: _body),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        FilledButton(
          key: const ValueKey('guardian_accept'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size.fromHeight(48)),
          onPressed: () => ref.read(guardianConsentProvider.notifier).accept(),
          child: Text(_t('guardian_consent_accept')),
        ),
      ];

  List<Widget> _controls() {
    final g = ref.watch(guardianProvider);
    final hasPhrase = ref.watch(guardianHasPhraseProvider);
    return [
      _statusCard(g),
      const SizedBox(height: 16),
      if (!g.active) ...[
        Text(_t('guardian_length'), style: _heading),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final d in guardianDurations)
              ChoiceChip(
                key: ValueKey('guardian_length_${d.inHours}'),
                label: Text(_t('guardian_hours').replaceAll('{n}', '${d.inHours}')),
                selected: _length == d,
                onSelected: (_) => setState(() => _length = d),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
      FilledButton(
        key: ValueKey(g.active ? 'guardian_stop' : 'guardian_start'),
        style: FilledButton.styleFrom(
          backgroundColor: g.active ? AppColors.emergency : AppColors.primary,
          minimumSize: const Size.fromHeight(52),
        ),
        onPressed: _starting
            ? null
            : g.active
                ? () => ref.read(guardianProvider.notifier).stop()
                : _start,
        child: Text(_t(g.active ? 'guardian_stop' : 'guardian_start')),
      ),
      const SizedBox(height: 24),
      // Not while a session runs: the phrase is read when a session starts.
      if (!g.active) ..._phraseSection(hasPhrase),
      const SizedBox(height: 24),
      Text(_t('guardian_consent_limits'), style: _body.copyWith(color: AppColors.textDim, fontSize: 13)),
    ];
  }

  List<Widget> _phraseSection(bool hasPhrase) => [
        Text(_t('guardian_phrase_heading'), style: _heading),
        const SizedBox(height: 6),
        Text(_t('guardian_phrase_desc'), style: _body.copyWith(color: AppColors.textDim, fontSize: 13)),
        const SizedBox(height: 8),
        Text(
          _t(hasPhrase ? 'guardian_phrase_set' : 'guardian_phrase_not_set'),
          key: const ValueKey('guardian_phrase_status'),
          style: _body,
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('guardian_phrase_field'),
          controller: _phrase,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: _t('guardian_phrase_hint'),
            border: const OutlineInputBorder(),
          ),
        ),
        if (_phraseMessage != null) ...[
          const SizedBox(height: 6),
          Text(
            _phraseMessage!,
            style: _body.copyWith(
                fontSize: 13,
                color: _phraseMessageIsError ? AppColors.emergency : AppColors.success,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: OutlinedButton(
                  key: const ValueKey('guardian_phrase_save'),
                  onPressed: _savePhrase,
                  child: Text(_t('guardian_phrase_save')),
                ),
            ),
            if (hasPhrase) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton(
                    key: const ValueKey('guardian_phrase_remove'),
                    onPressed: () => ref.read(guardianHasPhraseProvider.notifier).remove(),
                    child: Text(_t('guardian_phrase_remove')),
                  ),
                ),
            ],
          ],
        ),
      ];

  Widget _statusCard(GuardianState g) {
    final String line;
    var colour = AppColors.textDim;
    if (g.active) {
      colour = AppColors.success;
      if (g.pausedInBackground) {
        line = _t('guardian_paused_background');
        colour = AppColors.warning;
      } else if (g.pausedForOtherFeature) {
        line = _t('guardian_paused_dictation');
        colour = AppColors.warning;
      } else {
        line = _t('guardian_listening_until')
            .replaceAll('{time}', TimeOfDay.fromDateTime(g.endsAt!).format(context));
      }
    } else if (g.problem != null) {
      colour = AppColors.emergency;
      line = _t(switch (g.problem!) {
        GuardianProblem.unsupported => 'guardian_problem_unsupported',
        GuardianProblem.microphoneDenied => 'guardian_problem_mic',
        GuardianProblem.recognizerUnavailable => 'guardian_problem_recognizer',
        GuardianProblem.recognizerKeepsFailing => 'guardian_problem_failing',
      });
    } else if (g.lastMatch != null) {
      colour = AppColors.emergency;
      line = _t('guardian_sent');
    } else {
      line = _t('guardian_off');
    }
    return Container(
      key: const ValueKey('guardian_status'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colour, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(g.listening ? Icons.hearing : Icons.hearing_disabled, color: colour),
          const SizedBox(width: 12),
          Expanded(child: Text(line, style: _body.copyWith(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    await ref.read(guardianProvider.notifier).start(_length);
    if (mounted) setState(() => _starting = false);
  }

  Future<void> _savePhrase() async {
    final problem = await ref.read(guardianHasPhraseProvider.notifier).save(_phrase.text);
    if (!mounted) return;
    setState(() {
      _phraseMessageIsError = problem != null;
      _phraseMessage = _t(switch (problem) {
        SecretPhraseProblem.tooShort => 'guardian_phrase_too_short',
        SecretPhraseProblem.tooCommon => 'guardian_phrase_too_common',
        null => 'guardian_phrase_saved',
      });
      if (problem == null) _phrase.clear();
    });
  }
}
