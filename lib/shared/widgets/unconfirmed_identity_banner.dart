import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/shared/localization/translations.dart';

/// Says when the app opened without being able to ask who this account is.
///
/// ## Why it has to say anything
///
/// Until T-100 the app did not start without a network at all: `resolveRole()`
/// issued an unbounded profile fetch, `computeRedirect()` holds the router on
/// the splash while that is in flight, and the only guard was a one-shot timer
/// that had already fired. The handset sat on the splash for as long as the
/// operating system takes to abandon a TCP connection, then went to a login
/// screen that offline cannot succeed.
///
/// It now opens from what this handset last resolved. That is the right
/// behaviour and it is not free: a responder whose rung changed this morning is
/// being shown a board chosen from yesterday's answer. So the screen says so,
/// with the date, rather than looking identical to a confirmed session.
///
/// It is NOT a security control and must not be read as one. The server still
/// refuses this handset everything the account is not entitled to; this decides
/// which screen opens, and being wrong costs a screen whose data will not load.
///
/// Returns nothing at all when the identity was confirmed by the server, which
/// is the ordinary case — a banner that is always there is wallpaper.
class UnconfirmedIdentityBanner extends ConsumerWidget {
  /// Documentation for this public member.
  const UnconfirmedIdentityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (!auth.roleFromCache) return const SizedBox.shrink();

    final lang = ref.watch(languageProvider);
    final at = auth.roleConfirmedAt;
    // A date, not "2 days ago": an operator reading this is deciding whether
    // to trust a rung, and "Tue 21 Oct" is a thing they can reason about
    // against when they were last reassigned.
    final when = at == null
        ? '—'
        : '${at.day.toString().padLeft(2, '0')}/'
            '${at.month.toString().padLeft(2, '0')}/${at.year}';

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          border: Border(
            bottom: BorderSide(
              color: AppColors.warning.withValues(alpha: 0.4),
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 14,
              color: AppColors.warning,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                Translations.get('auth_working_from_record', lang)
                    .replaceAll('{when}', when),
                style: GoogleFonts.outfit(
                  color: AppColors.warning,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
