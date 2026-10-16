import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';

/// The reporter's voice, played inside the app.
///
/// ## What this replaces
///
/// Both screens that could show an audio attachment handed the url to the
/// platform and hoped. `mission_intel_screen.dart` drew a microphone with
/// **TAP TO PLAY** under it and called `launchUrl()`; the HQ console opened a
/// new browser tab. On a handset that means leaving Plateau Eye in the
/// middle of an incident — and this app has a re-entry lock that engages when
/// it has been away from the foreground, so playing a voice note could cost a
/// responder a code prompt to get back to the incident they were working.
/// Whether the audio played at all then depended on what the phone does with
/// an `.m4a` url, which for a Cloudinary `/raw/` link is often a download.
///
/// So it plays here, in the card, and the states it can be in are all SAID:
/// loading, playing, paused, and — the one that matters — failed, with the
/// reason. A play button that does nothing and says nothing is how a responder
/// concludes a reporter sent silence.
class VoiceNotePlayer extends StatefulWidget {
  /// Creates a player for one voice note.
  const VoiceNotePlayer({
    required this.url,
    this.seconds,
    this.label = 'VOICE NOTE FROM THE REPORTER',
    this.player,
    super.key,
  });

  /// Where the recording is.
  final String url;

  /// Its length, as the row recorded it. Shown BEFORE anything is fetched, so
  /// somebody on a weak connection knows what they are about to pull.
  final int? seconds;

  /// What this recording is, in the card's own words.
  final String label;

  /// A seam for tests: the real one needs a platform channel.
  final AudioPlayer? player;

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  late final AudioPlayer _player = widget.player ?? AudioPlayer();
  StreamSubscription<PlayerState>? _states;
  bool _loading = false;
  bool _ready = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _states = _player.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_states?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  String _stamp(Duration? d) {
    final total = d?.inSeconds ?? widget.seconds ?? 0;
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _toggle() async {
    if (_failure != null) {
      // A second press after a failure RETRIES rather than doing nothing. The
      // usual cause is a dropped connection, which is the usual thing to have
      // changed by the time somebody presses again.
      setState(() => _failure = null);
    }
    try {
      if (!_ready) {
        setState(() => _loading = true);
        await _player.setUrl(widget.url);
        _ready = true;
      }
      if (_player.playing) {
        await _player.pause();
      } else {
        // Replay from the start once it has run to the end, rather than
        // sitting at the end doing nothing on every later press.
        final at = _player.position;
        final end = _player.duration;
        if (end != null && at >= end) await _player.seek(Duration.zero);
        await _player.play();
      }
    } on Object catch (e) {
      // SAID, not swallowed. This is the screen where a responder finds out
      // what the person reporting actually told them.
      setState(() {
        _failure = 'This voice note did not play on this phone.';
        _ready = false;
      });
      debugPrint('[VOICE_NOTE_PLAYER] $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playing = _player.playing;
    final position = _ready ? _player.position : null;
    final duration = _player.duration;
    final progress =
        (duration != null && duration.inMilliseconds > 0 && position != null)
            ? (position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0)
            : 0.0;

    return Semantics(
      container: true,
      label: widget.label,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _failure != null ? AppColors.danger : AppColors.primary,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.graphic_eq_rounded,
                  color: AppColors.primary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label,
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                Text(
                  _stamp(position ?? duration),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textDim,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                // One button, whose accessible name says which of the two
                // things pressing it will do.
                Semantics(
                  button: true,
                  label: playing
                      ? 'Pause the voice note'
                      : 'Play the voice note',
                  excludeSemantics: true,
                  onTap: _toggle,
                  child: InkWell(
                    onTap: _loading ? null : _toggle,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: _loading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          : Icon(
                              playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: AppColors.primary,
                              size: 26,
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: AppColors.outline,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            if (_failure != null) ...[
              const SizedBox(height: 8),
              Text(
                '$_failure Press play to try again.',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
