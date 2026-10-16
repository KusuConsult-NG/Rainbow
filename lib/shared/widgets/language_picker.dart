import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/shared/localization/translations.dart';

/// The one control that changes the app's language.
///
/// ## Why this exists
///
/// There were two providers called `languageProvider`, each with a class called
/// `LanguageNotifier`, and which one a file got depended on which it imported:
///
///   * `shared/localization/translations.dart` — stores `app_lang` as `'ha'`,
///     and is what every screen that reads a translated string watches;
///   * `providers/language_provider.dart` — stored `app_language` as `'HA'`,
///     and was imported by nothing.
///
/// The Settings screen imported neither. It kept a private `_language` string
/// and wrote `app_language` straight to SharedPreferences, so **choosing Hausa
/// in Settings changed nothing at all** — a dropdown wired to a key no reader
/// has ever heard of. The only working picker was a flag button on the home
/// screen.
///
/// So: one widget, one provider, used by Settings and by first-run setup. The
/// dead provider is deleted rather than left to be imported by accident.
class LanguagePicker extends ConsumerWidget {
  /// Creates the language picker.
  const LanguagePicker({this.compact = false, super.key});

  /// Drops the explanatory line, for a screen that has its own heading.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(languageProvider);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.language_rounded,
                color: AppColors.primary,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(
                Translations.get('choose_language', current),
                style: GoogleFonts.outfit(
                  color: AppColors.onBackground,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 6),
            Text(
              Translations.get('choose_language_desc', current),
              style: GoogleFonts.inter(color: AppColors.textDim, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              for (final language in AppLanguage.values) ...[
                Expanded(
                  child: _LanguageChip(
                    language: language,
                    selected: language == current,
                    onTap: () => ref
                        .read(languageProvider.notifier)
                        .setLanguage(language),
                  ),
                ),
                if (language != AppLanguage.values.last)
                  const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final AppLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // ONE semantics node carrying all four facts: that this is a button, what
    // it is called, whether it is the current language, and the tap. Named for
    // the LANGUAGE, not for a flag — `check_control_labels.py` exists because
    // controls here had empty accessible names, and an emoji is not a name.
    //
    // The first version put the Semantics INSIDE the InkWell, which split those
    // facts across two nodes: the outer one had the button role and the tap,
    // the inner one the label and the selection. A screen reader announces
    // "English" and then, separately, "selected" — and the browser harness,
    // which reads the node it is about to press, saw a button with no selection
    // state and reported the chip for the one language already in use as a
    // control that does nothing. Pressing the chosen option IS meant to do
    // nothing; the node has to say it is the chosen option. Same shape as the
    // report subtype rows, which had this settled already.
    return Semantics(
      button: true,
      label: language.label,
      selected: selected,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.outline,
            ),
          ),
          child: Center(
            child: Text(
              language.label,
              style: GoogleFonts.outfit(
                color: selected ? AppColors.primary : AppColors.textSecondary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
