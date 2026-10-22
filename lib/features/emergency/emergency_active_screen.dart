// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/features/emergency/pending_evidence.dart';
import 'package:rainbow_app/providers/emergency_provider.dart';
import 'package:rainbow_app/services/alert_media.dart';
import 'package:rainbow_app/services/cloudinary_service.dart';
import 'package:rainbow_app/services/live_stream_service.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/shared/localization/translations.dart';
import 'package:rainbow_app/shared/widgets/rainbow_map.dart';
import 'package:rainbow_app/shared/widgets/safety_feedback_dialog.dart';


/// Documentation for this public member.

class EmergencyActiveScreen extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const EmergencyActiveScreen({super.key});

  @override
  ConsumerState<EmergencyActiveScreen> createState() =>
      _EmergencyActiveScreenState();
}

class _EmergencyActiveScreenState extends ConsumerState<EmergencyActiveScreen>
    with TickerProviderStateMixin {
  Timer? _tickTimer;
  late AnimationController _cancelController;
  late AnimationController _pulseController;
  Timer? _cancelTimer;

  bool _showMap = false;
  bool _isCapturingEvidence = false;

  /// Photographs taken before the SOS had an incident to attach them to.
  /// See pending_evidence.dart for why holding them is the whole point.
  final PendingEvidence _pending = PendingEvidence();

  /// Whether a flush has been started for the incident id we have now, so the
  /// per-second timer tick on this screen cannot start a second one.
  String? _flushedFor;

  /// Send everything held, now that [alertId] exists.
  ///
  /// Anything that does not make it stays held and the marker is cleared, so the
  /// next confirmation — or the next photograph — tries again rather than
  /// leaving the queue stranded.
  void _flushHeldEvidence(String alertId) {
    if (_pending.isEmpty || _flushedFor == alertId) return;
    _flushedFor = alertId;
    unawaited(
      _pending.flush((path) => _attachOne(path, alertId)).then((res) async {
        if (res.stillHeld > 0) _flushedFor = null;
        if (!res.anythingDelivered) return;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(deliveredEvidenceMessage(res.delivered.length)),
            backgroundColor: AppColors.success,
          ),
        );
      }),
    );
  }

  /// Upload one local file and attach it to [alertId].
  ///
  /// Returns whether the file is now ON the incident. A refusal and a transport
  /// failure both answer false, and both mean the caller keeps the file — see
  /// AttachResult.isOnTheIncident.
  Future<bool> _attachOne(String path, String alertId) async {
    final url = await CloudinaryService.instance.uploadMedia(File(path));
    if (url == null) return false;
    final res = await AlertMedia.append(alertId, [url]);
    return res.isOnTheIncident;
  }

  @override
  void initState() {
    super.initState();
    _cancelController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    unawaited(_pulseController.repeat(reverse: true));

    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) ref.read(emergencyProvider.notifier).tick();
    });

    unawaited(
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _showMap = true);
          unawaited(HapticFeedback.lightImpact());
        }
      }),
    );
  }

  bool _isLiveStreaming = false;

  @override
  void dispose() {
    _tickTimer?.cancel();
    _cancelTimer?.cancel();
    _cancelController.dispose();
    _pulseController.dispose();
    if (_isLiveStreaming) {
      unawaited(LiveStreamService().stopStream());
    }
    super.dispose();
  }

  Future<void> _toggleLiveStream() async {
    final alertId = ref.read(emergencyProvider).alertId;
    if (alertId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('eme_wait_before_stream'))),
        );
      }
      return;
    }
    if (_isLiveStreaming) {
      await LiveStreamService().stopStream();
      if (mounted) setState(() => _isLiveStreaming = false);
    } else {
      final success = await LiveStreamService().startStream(alertId);
      if (mounted) {
        setState(() => _isLiveStreaming = success);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? '🔴 ${_t('eme_broadcast_live')}'
                  : _t('eme_stream_failed'),
            ),
            backgroundColor: success ? AppColors.danger : AppColors.surfaceContainerHighest,
          ),
        );
      }
    }
  }


  Future<void> _captureEvidence() async {
    if (_isCapturingEvidence) return;
    setState(() => _isCapturingEvidence = true);
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 60,
      );
      if (photo == null) {
        setState(() => _isCapturingEvidence = false);
        return;
      }
      final alertId = ref.read(emergencyProvider).alertId;
      if (alertId == null) {
        // The SOS has not round-tripped yet. This used to say "evidence saved
        // locally" and then DROP the path — nothing recorded it and nothing
        // retried, so the photograph was gone. That window is the first seconds
        // of the emergency, which is usually the only moment the person gets.
        //
        // Held instead, and flushed by the listener in build() the moment an
        // incident id exists. See pending_evidence.dart.
        _pending.hold(photo.path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(heldEvidenceMessage(_pending.count))),
          );
        }
        setState(() => _isCapturingEvidence = false);
        return;
      }
      // Upload in the background — the person should not be made to watch a
      // progress bar during a duress event. Failure HOLDS the file rather than
      // discarding it, so the next flush tries again.
      unawaited(
        _attachOne(photo.path, alertId).then((ok) {
          if (!ok) {
            _pending.hold(photo.path);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(heldEvidenceMessage(_pending.count))),
              );
            }
            return;
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('📷 Evidence captured and sent to HQ'),
                backgroundColor: AppColors.success,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }),
      );
    } catch (e) {
      debugPrint('[SOS_CAPTURE_ERR] $e');
    } finally {
      if (mounted) setState(() => _isCapturingEvidence = false);
    }
  }

  void _startCancel() {
    unawaited(HapticFeedback.mediumImpact());
    unawaited(_cancelController.forward());
    _cancelTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      unawaited(HapticFeedback.heavyImpact());
      unawaited(_cancelController.reverse());
      _showPinVerification();
    });
  }

  void _stopCancel() {
    _cancelTimer?.cancel();
    unawaited(_cancelController.reverse());
  }

  void _showPinVerification() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: false,
        enableDrag: false,
        builder: (ctx) => _TacticalPinVerification(
          onVerified: () async {
            if (!mounted) return;
            final alertId = ref.read(emergencyProvider).alertId;
            await showSafetyFeedback(context, alertId: alertId);
            if (mounted) context.go(AppRoutes.home);
          },
        ),
      ),
    );
  }

  /// The language this citizen chose, for the labels on this screen.
  AppLanguage get _lang => ref.watch(languageProvider);

  /// Shorthand for a translated label on this screen.
  String _t(String key) => Translations.get(key, _lang);

  @override
  Widget build(BuildContext context) {
    final emergencyState = ref.watch(emergencyProvider);

    // Send anything photographed before the SOS had an incident to attach it to.
    //
    // `ref.listen` on the id ALONE, not a plain statement in build and not a
    // listen on the whole state. This screen's timer ticks every second, so both
    // of those would fire sixty times a minute; selecting the id means this runs
    // exactly once, when the SOS is confirmed.
    ref.listen<String?>(
      emergencyProvider.select((s) => s.alertId),
      (previous, next) {
        if (next == null || next == previous) return;
        _flushHeldEvidence(next);
      },
    );
    final locAsync = ref.watch(userLocationStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Ambient Emergency Glow
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    // Both stops OPAQUE. This pulse used to run from
                    // `emergency` at up to 15% alpha to an opaque
                    // `background`, and a gradient between a translucent
                    // colour and an opaque one passes through ~50% alpha
                    // halfway along — which at `radius: 1.5` is most of the
                    // screen. The live SOS screen washed out to a muddy
                    // pink-grey on every beat. Blending the pulse down onto
                    // the background first keeps the breath and drops the
                    // mud.
                    gradient: RadialGradient(
                      center: Alignment.topCenter,
                      radius: 1.5,
                      colors: [
                        Color.alphaBlend(
                          AppColors.emergency.withValues(
                            alpha: 0.15 * _pulseController.value,
                          ),
                          AppColors.background,
                        ),
                        AppColors.background,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _buildHeader(emergencyState.elapsedSeconds),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        _buildStatusCard(),
                        const SizedBox(height: 24),
                        Expanded(child: _buildTacticalMap(locAsync)),
                        const SizedBox(height: 24),
                        _buildTelemetryGrid(locAsync),
                      ],
                    ),
                  ),
                ),

                // Action Buttons: Evidence Capture & Live Stream
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isCapturingEvidence ? null : _captureEvidence,
                          icon: _isCapturingEvidence
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.warning))
                              : const Icon(Icons.camera_alt_rounded, size: 16, color: AppColors.warning),
                          label: Text(
                            _isCapturingEvidence
                                ? _t('eme_capturing')
                                : _t('eme_photo_evidence'),
                            style: GoogleFonts.outfit(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                              letterSpacing: 1,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.warning, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _toggleLiveStream,
                          icon: Icon(
                            _isLiveStreaming ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                          label: Text(
                            _isLiveStreaming
                                ? _t('eme_stop_stream')
                                : _t('eme_broadcast_live'),
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                              letterSpacing: 1,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isLiveStreaming ? AppColors.danger : AppColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Dispatcher Chat button for citizen
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: _DispatcherChatButton(),
                ),

                _buildCancelControl(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    final timerStr =
        '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t('eme_active'),
                style: GoogleFonts.outfit(
                  color: AppColors.emergency,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
              Text(
                _t('eme_live_telemetry'),
                style: GoogleFonts.outfit(
                  color: AppColors.textDim,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.emergency.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppColors.emergency.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.emergency,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  timerStr,
                  style: GoogleFonts.outfit(
                    color: AppColors.onBackground,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final alertId = ref.watch(emergencyProvider).alertId;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: AppColors.glassSurface,
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: alertId != null
            ? SupabaseConfig.client
                .from('alerts')
                .stream(primaryKey: ['id'])
                .eq('id', alertId)
            : const Stream.empty(),
        builder: (context, snapshot) {
          var statusText = _t('eme_link_establishing');
          var statusTitle = _t('eme_signal_established');
          var titleColor = AppColors.onBackground;

          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
            final alert = snapshot.data!.first;
            final status = (alert['status'] as String? ?? 'PENDING').toUpperCase();
            if (status == 'DISPATCHED') {
              statusTitle = _t('eme_squad_dispatched');
              statusText = _t('eme_squad_dispatched_desc');
              titleColor = AppColors.accent;
            } else if (status == 'ACKNOWLEDGED' || status == 'ON_ROUTE') {
              statusTitle = _t('eme_en_route');
              statusText = _t('eme_en_route_desc');
              titleColor = AppColors.primary;
            } else if (status == 'ON_SITE') {
              statusTitle = _t('eme_on_site');
              statusText = _t('eme_on_site_desc');
              titleColor = AppColors.success;
            } else if (status == 'RESOLVED') {
              statusTitle = _t('eme_secured');
              statusText = _t('eme_secured_desc');
              titleColor = AppColors.success;
            } else {
              statusTitle = _t('eme_broadcasting');
              statusText = _t('eme_broadcasting_triaging');
              titleColor = AppColors.primary;
            }
          } else if (_showMap) {
            statusTitle = _t('eme_broadcasting');
            statusText = _t('eme_broadcasting_notified');
            titleColor = AppColors.primary;
          }

          return Column(
            children: [
              Text(
                statusTitle,
                style: GoogleFonts.outfit(
                  color: titleColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                statusText,
                style: GoogleFonts.outfit(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTacticalMap(AsyncValue<Position?> locAsync) {
    return AnimatedOpacity(
      opacity: _showMap ? 1.0 : 0.0,
      duration: const Duration(seconds: 1),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: AppColors.glassBorder,
          boxShadow: [
            BoxShadow(
              color: AppColors.emergency.withValues(alpha: 0.05),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            locAsync.when(
              data: (pos) => pos != null
                  ? RainbowMap(
                      label: _t('eme_semantics_map_label'),
                      center: LatLng(pos.latitude, pos.longitude),
                      initialZoom: 17,
                      interactive: false,
                    )
                  : Container(color: AppColors.surface),
              loading: () => ColoredBox(
                color: AppColors.surface,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        color: AppColors.emergency,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _t('eme_scanning'),
                        style: GoogleFonts.outfit(
                          color: AppColors.emergency,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              error: (_, __) => Container(color: AppColors.surface),
            ),
            // Tactical Scanning Overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background.withValues(alpha: 0.6),
                    Colors.transparent,
                    AppColors.background.withValues(alpha: 0.6),
                  ],
                ),
              ),
            ),
            // Pulse at center
            const Center(
              child: _PulseMarker(color: AppColors.emergency),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryGrid(AsyncValue<Position?> locAsync) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          _TelemetryItem(
            label: _t('eme_latitude'),
            value: locAsync.when(
              data: (pos) => pos?.latitude.toStringAsFixed(5) ?? '---',
              loading: () => '---',
              error: (_, __) => 'ERR',
            ),
          ),
          _TelemetryItem(
            label: _t('eme_longitude'),
            value: locAsync.when(
              data: (pos) => pos?.longitude.toStringAsFixed(5) ?? '---',
              loading: () => '---',
              error: (_, __) => 'ERR',
            ),
          ),
          _TelemetryItem(
            label: _t('eme_accuracy'),
            value: locAsync.when(
              data: (pos) => pos != null ? '${pos.accuracy.toInt()}m' : '---',
              loading: () => '---',
              error: (_, __) => 'ERR',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCancelControl() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onLongPressStart: (_) => _startCancel(),
        onLongPressEnd: (_) => _stopCancel(),
        onLongPressCancel: _stopCancel,
        child: AnimatedBuilder(
          animation: _cancelController,
          builder: (context, _) {
            return Container(
              height: 80,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                  color: Color.lerp(
                    AppColors.outline,
                    AppColors.emergency,
                    _cancelController.value,
                  )!,
                ),
              ),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _cancelController.value,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.emergency.withValues(alpha: 0.2),
                              AppColors.emergency.withValues(alpha: 0.5),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.security,
                        color: _cancelController.value > 0.5
                            ? Colors.white
                            : AppColors.textDim,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _cancelController.value > 0.1
                            ? _t('eme_verifying_safety')
                            : _t('eme_hold_to_cancel'),
                        style: GoogleFonts.outfit(
                          color: _cancelController.value > 0.5
                              ? Colors.white
                              : AppColors.onBackground,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TelemetryItem extends StatelessWidget {
  const _TelemetryItem({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              color: AppColors.textDim,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: AppColors.onBackground,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TacticalPinVerification extends ConsumerStatefulWidget {
  const _TacticalPinVerification({required this.onVerified});
  final VoidCallback onVerified;

  @override
  ConsumerState<_TacticalPinVerification> createState() =>
      _TacticalPinVerificationState();
}

class _TacticalPinVerificationState
    extends ConsumerState<_TacticalPinVerification> {
  /// Shorthand for a translated label on this sheet.
  String _t(String key) => Translations.get(key, ref.watch(languageProvider));
  String pin = '';
  bool _verifying = false;

  // PINs are per-user and server-verified, so the pad cannot know a length in
  // advance. It accepts 4–8 digits and submits on the ✓ key.
  static const int _minPinLength = 4;
  static const int _maxPinLength = 8;

  @override
  Widget build(BuildContext context) {
    final pinLength = pin.length < _minPinLength ? _minPinLength : pin.length;
    final horizontalMargin = pinLength > 4 ? 8.0 : 16.0;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 32,
          bottom: MediaQuery.of(context).viewInsets.bottom + 48,
        ),
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.85),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textDim,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              _t('eme_security_verification'),
              style: GoogleFonts.outfit(
                color: AppColors.emergency,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _t('eme_enter_pin'),
              style: GoogleFonts.outfit(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 40),

            // PIN Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                pin.length > pinLength ? pin.length : pinLength,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index < pin.length
                        ? AppColors.emergency
                        : AppColors.outline,
                    boxShadow: index < pin.length
                        ? [
                            BoxShadow(
                              color: AppColors.emergency.withValues(alpha: 0.5),
                              blurRadius: 10,
                            ),
                          ]
                        : [],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),

            // Numpad
            _buildNumpad(),
          ],
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    return Column(
      children: [
        for (var i = 0; i < 3; i++) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var j = 1; j <= 3; j++) _buildKey(i * 3 + j),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildSubmit(),
            _buildKey(0),
            _buildBackspace(),
          ],
        ),
      ],
    );
  }

  Widget _buildKey(int number) {
    return GestureDetector(
      onTap: () {
        unawaited(HapticFeedback.lightImpact());
        if (_verifying) return;
        if (pin.length >= _maxPinLength) {
          unawaited(HapticFeedback.vibrate());
          return;
        }
        setState(() => pin = pin + number.toString());
      },
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.03),
          border: Border.all(color: AppColors.outline),
        ),
        child: Center(
          child: Text(
            number.toString(),
            style: GoogleFonts.outfit(
              color: AppColors.onBackground,
              fontSize: 32,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (pin.length < _minPinLength || _verifying) return;
    setState(() => _verifying = true);
    final outcome =
        await ref.read(emergencyProvider.notifier).verifyCancellation(pin);
    if (!mounted) return;
    setState(() => _verifying = false);

    switch (outcome) {
      // Identical handling on purpose. A captor watching the screen must not
      // be able to tell which code was entered.
      case CancelOutcome.resolved:
      case CancelOutcome.duress:
        Navigator.of(context).pop();
        widget.onVerified();
      case CancelOutcome.unset:
        _say('${_t('eme_no_pin_set')}${_t('eme_set_pin_hint')}');
      case CancelOutcome.locked:
        _say(_t('eme_pin_locked'));
        setState(() => pin = '');
      case CancelOutcome.error:
        _say(_t('eme_pin_unverified'));
      case CancelOutcome.invalid:
      case CancelOutcome.notFound:
        unawaited(HapticFeedback.vibrate());
        setState(() => pin = '');
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildSubmit() {
    final enabled = pin.length >= _minPinLength && !_verifying;
    // This is the control that ends an emergency, and it was a circle with a
    // tick in it and no accessible name at all. A screen-reader user on this
    // screen was offered an unnamed button, next to another unnamed button
    // that deletes a digit.
    //
    // The name says what the state is, because the same control is disabled
    // until the PIN is long enough and busy while it is being checked —
    // "nothing is happening" and "it will not accept this" must not sound
    // alike. `onTap` is on the Semantics too: `excludeSemantics` takes the
    // child's tap action away with its semantics.
    return Semantics(
      button: true,
      enabled: enabled,
      label: _verifying
          ? _t('eme_semantics_pin_checking')
          : enabled
              ? _t('eme_semantics_pin_submit')
              : _t('eme_semantics_pin_submit_short')
                  .replaceAll('{count}', '$_minPinLength'),
      excludeSemantics: true,
      onTap: enabled ? _submit : null,
      child: GestureDetector(
        onTap: enabled ? _submit : null,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled
                ? AppColors.emergency.withValues(alpha: 0.15)
                : Colors.transparent,
            border: Border.all(
              color: enabled ? AppColors.emergency : AppColors.outline,
            ),
          ),
          child: Center(
            child: _verifying
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.emergency,
                    ),
                  )
                : Icon(
                    Icons.check_rounded,
                    color: enabled ? AppColors.emergency : AppColors.textDim,
                    size: 32,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspace() {
    return Semantics(
      button: true,
      label: _t('eme_semantics_pin_backspace'),
      excludeSemantics: true,
      onTap: () {
        unawaited(HapticFeedback.lightImpact());
        if (pin.isNotEmpty) {
          setState(() => pin = pin.substring(0, pin.length - 1));
        }
      },
      child: GestureDetector(
        onTap: () {
          unawaited(HapticFeedback.lightImpact());
          if (pin.isNotEmpty) {
            setState(() => pin = pin.substring(0, pin.length - 1));
          }
        },
        child: Container(
          width: 80,
          height: 80,
          decoration: const BoxDecoration(shape: BoxShape.circle),
          child: const Center(
            child: Icon(
              Icons.backspace_outlined,
              color: AppColors.textSecondary,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}

/// Fetches the user's most recent open alert and opens the dispatcher chat.
class _DispatcherChatButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertId = ref.watch(emergencyProvider).alertId;
    String t(String key) => Translations.get(key, ref.watch(languageProvider));

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: alertId == null
            ? null
            : () {
                unawaited(
                  context.push(AppRoutes.dispatcherChat, extra: alertId),
                );
              },
        icon: const Icon(Icons.headset_mic_rounded, size: 18),
        label: Text(
          alertId == null
              ? t('eme_awaiting_dispatch_link')
              : t('eme_contact_dispatcher'),
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 1.5,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          side: BorderSide(
            color: AppColors.accent.withValues(alpha: 0.4),
            width: 1.5,
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _PulseMarker extends StatefulWidget {
  const _PulseMarker({required this.color});
  final Color color;

  @override
  State<_PulseMarker> createState() => _PulseMarkerState();
}

class _PulseMarkerState extends State<_PulseMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    unawaited(_controller.repeat());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 60 * _controller.value,
              height: 60 * _controller.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.color.withValues(alpha: 1 - _controller.value),
                  width: 2,
                ),
              ),
            ),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
