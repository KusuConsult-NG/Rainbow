/// Opening a piece of incident evidence on the phone.
///
/// Videos used to open a black dialog with a play icon that did nothing, and
/// on the mission card a voice note did the same. A video now opens in the
/// phone's own player — no new video library, which would have raised the
/// app's minimum Flutter version for everyone — and a voice note plays in a
/// sheet, as it already did on Mission Intel.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/shared/widgets/voice_note_player.dart';
import 'package:url_launcher/url_launcher.dart';

enum EvidenceKind { photo, video, audio }

/// What kind of file [url] is, from its address. Cloudinary puts videos under
/// /video/ and audio under /raw/.
EvidenceKind evidenceKindOf(String url) {
  final u = url.toLowerCase();
  if (u.contains('/video/') ||
      u.endsWith('.mp4') ||
      u.endsWith('.mov') ||
      u.endsWith('.webm')) {
    return EvidenceKind.video;
  }
  if (u.contains('/raw/') ||
      u.endsWith('.m4a') ||
      u.endsWith('.mp3') ||
      u.endsWith('.wav')) {
    return EvidenceKind.audio;
  }
  return EvidenceKind.photo;
}

@visibleForTesting
Future<bool> Function(Uri uri)? openExternallyOverride;

Future<bool> _openExternally(Uri uri) async {
  final override = openExternallyOverride;
  if (override != null) return override(uri);
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Opens [url] the way its kind needs.
Future<void> openEvidence(BuildContext context, String url) async {
  switch (evidenceKindOf(url)) {
    case EvidenceKind.video:
      var opened = false;
      try {
        opened = await _openExternally(Uri.parse(url));
      } on Object catch (_) {
        opened = false;
      }
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This phone could not open the video. It is still on the '
              'incident; HQ can play it from the console.',
            ),
          ),
        );
      }
    case EvidenceKind.audio:
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.background,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(20),
          child: VoiceNotePlayer(
            url: url,
            label: 'RECORDING ATTACHED TO THIS INCIDENT',
          ),
        ),
      );
    case EvidenceKind.photo:
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.black,
          child: InteractiveViewer(child: Image.network(url)),
        ),
      );
  }
}

/// The same, for a handler that does not wait.
void openEvidenceUnawaited(BuildContext context, String url) =>
    unawaited(openEvidence(context, url));
