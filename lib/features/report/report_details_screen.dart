// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rainbow_app/core/constants/alert_categories.dart';
import 'package:rainbow_app/core/constants/tactical_mapping.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/models/alert_model.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/auth_service.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/services/speech_service.dart';
import 'package:rainbow_app/services/sync_service.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';
import 'package:record/record.dart';
import 'package:rainbow_app/services/voice_note_service.dart';
import 'package:rainbow_app/shared/localization/translations.dart';

/// Documentation for this public member.

/// What to tell somebody whose attachment did not work.
///
/// Split out from the screen because the CHOICE is the part worth pinning: a
/// refused permission is the one cause the person can act on, so it is named,
/// and everything else says plainly that it did not work here. Both endings
/// say what they can still do, because the report matters more than the photo
/// and a dead end mid-emergency is how a report gets abandoned.
String attachmentErrorMessage(Object error, [AppLanguage lang = AppLanguage.english]) {
  final text = error.toString().toLowerCase();
  final denied = text.contains('permission') ||
      text.contains('denied') ||
      text.contains('access');
  return denied
      ? Translations.get('rpt_camera_denied', lang)
      : Translations.get('rpt_attachment_failed', lang);
}

class ReportDetailsScreen extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const ReportDetailsScreen({
    required this.categoryInfo,
    required this.subType,
    super.key,
  });

  /// Documentation for this public member.
  final AlertCategoryInfo categoryInfo;

  /// Documentation for this public member.
  final String subType;

  @override
  ConsumerState<ReportDetailsScreen> createState() =>
      _ReportDetailsScreenState();
}

class _ReportDetailsScreenState extends ConsumerState<ReportDetailsScreen> {
  final _narrativeCtrl = TextEditingController();
  bool _shareLocation = true;
  bool _manualOverride = false;
  bool _anonymous = false;
  bool _submitting = false;

  TacticalJurisdiction? _selectedLga;
  TacticalWard? _selectedWard;
  TacticalWard? _selectedSiecWard;
  String? _selectedPu;

  final List<File> _attachedFiles = [];
  /// Test seam: a real camera and gallery cannot be opened under test, and the
  /// failure path — a refused permission, an unavailable camera — is the one
  /// that was broken. Overriding the picker is how that path gets exercised.
  @visibleForTesting
  static ImagePicker Function()? pickerOverride;

  late final ImagePicker _picker = pickerOverride?.call() ?? ImagePicker();

  final _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordedAudioPath;
  DateTime? _recordingStartedAt;
  VoiceNote? _voiceNote;

  /// Tells the person something went wrong, rather than the console.
  ///
  /// Every one of the four attachment buttons called into image_picker with no
  /// error handling at all. `pickImage` and `pickVideo` THROW when the camera
  /// is unavailable or the permission has been refused — which on a real
  /// handset is the ordinary case, not an exotic one — and the exception went
  /// nowhere. Someone reporting an emergency pressed SCAN PHOTO, nothing
  /// happened, and there was nothing on the screen to say why or what to do.
  /// They would press it again.
  ///
  /// The browser sweep found all four dead and caught the thrown error.
  void _attachmentFailed(Object error) {
    debugPrint('[ATTACH_ERR] $error');
    if (!mounted) return;
    final lang = ref.read(languageProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(attachmentErrorMessage(error, lang)),
        backgroundColor: AppColors.emergency,
      ),
    );
  }

  /// Runs an attachment pick and keeps the file if one came back.
  ///
  /// Cancelling is NOT an error and says nothing: a person who changes their
  /// mind does not need to be told they changed their mind, and an emergency
  /// report is the wrong place to nag.
  Future<void> _attach(Future<XFile?> Function() pick) async {
    try {
      final file = await pick();
      if (file != null && mounted) {
        setState(() => _attachedFiles.add(File(file.path)));
      }
    } catch (e) {
      _attachmentFailed(e);
    }
  }

  Future<void> _pickImage() => _attach(
        () => _picker.pickImage(source: ImageSource.gallery, imageQuality: 70),
      );

  Future<void> _takePhoto() => _attach(
        () => _picker.pickImage(source: ImageSource.camera, imageQuality: 70),
      );

  Future<void> _pickVideo() =>
      _attach(() => _picker.pickVideo(source: ImageSource.gallery));

  Future<void> _takeVideo() =>
      _attach(() => _picker.pickVideo(source: ImageSource.camera));

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/audio_report_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        await _audioRecorder.start(
          const RecordConfig(
            
          ),
          path: path,
        );

        await SpeechService.instance.initialize();
        await SpeechService.instance.startListening(
          onResult: (text) {
            setState(() {
              _narrativeCtrl.text = text;
            });
          },
        );

        setState(() {
          _isRecording = true;
          _recordedAudioPath = null;
          _voiceNote = null;
          _recordingStartedAt = DateTime.now();
        });
      } else {
        // hasPermission() returning false skipped the whole body and said
        // nothing, so RECORD VOICE REPORT was a button that did nothing on any
        // handset where the microphone had been refused.
        if (!mounted) return;
        final lang = ref.read(languageProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Translations.get('rpt_mic_denied', lang),
            ),
            backgroundColor: AppColors.emergency,
          ),
        );
      }
    } catch (e) {
      // Was a debugPrint and nothing else: the failure reached the developer
      // console and never the person holding the phone.
      debugPrint('[AUDIO_REC] Start failed: $e');
      if (!mounted) return;
      final lang = ref.read(languageProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Translations.get('rpt_recorder_failed', lang),
          ),
          backgroundColor: AppColors.emergency,
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      await SpeechService.instance.stopListening();
      if (path != null) {
        final seconds = _recordingStartedAt == null
            ? 1
            : DateTime.now().difference(_recordingStartedAt!).inSeconds.clamp(
                1, VoiceNoteService.maxDuration.inSeconds);
        setState(() {
          _isRecording = false;
          _recordedAudioPath = path;
          // NOT added to `_attachedFiles` any more. That list is evidence —
          // the photograph of the vehicle, the video of the roadblock — and
          // uploading the reporter's own voice into it is why a responder's
          // card said "3 attachments" with no way to tell that one of them was
          // somebody speaking. It travels as the voice note instead.
          _voiceNote = VoiceNote(path: path, seconds: seconds);
          // The narrative is no longer stuffed with a placeholder. `[AUDIO_REPORT]
          // voice message recorded` was written into the field the reporter
          // was meant to type in, so it reached the console as the description
          // of the incident — an operator read a marker instead of a report.
          // An empty narrative is allowed now, because a voice note is a
          // report; see `_canSubmit`.
        });
      }
    } catch (e) {
      debugPrint('[AUDIO_REC] Stop failed: $e');
    }
  }

  void _deleteRecording() {
    if (_recordedAudioPath != null) {
      final file = File(_recordedAudioPath!);
      if (file.existsSync()) {
        file.deleteSync();
      }
      setState(() {
        _attachedFiles.removeWhere((f) => f.path == _recordedAudioPath);
        _recordedAudioPath = null;
        _voiceNote = null;
        // The narrative is the reporter's, not ours: it used to be CLEARED
        // when the recording was deleted, so typing a report and then
        // discarding a recording threw the typing away too.
      });
    }
  }

  @override
  void dispose() {
    _narrativeCtrl.dispose();
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);

    try {
      final lang = ref.read(languageProvider);
      final userId = ref.read(authServiceProvider).currentUserId ?? 'anonymous';
      // "No narrative provided" is the right wording for a report with
      // nothing in it and the wrong one for a report whose content is a
      // recording: an operator reading it on the board would pass over an
      // incident that has somebody's voice attached.
      final desc = _narrativeCtrl.text.isNotEmpty
          ? _narrativeCtrl.text
          : _voiceNote != null
              ? '[VOICE NOTE] The reporter left a ${_voiceNote!.label} voice '
                  'note and no text. Play the recording.'
              : Translations.get('rpt_no_narrative', lang);

      final connectivityResult = await Connectivity().checkConnectivity();
      final isOffline = connectivityResult.contains(ConnectivityResult.none);
      final userLoc = ref.read(userLocationStreamProvider).value;
      final lat = userLoc?.latitude;
      final lng = userLoc?.longitude;

      final priority = switch (widget.categoryInfo.priority) {
        'CRITICAL' => AlertPriority.critical,
        'HIGH' => AlertPriority.high,
        'MEDIUM' => AlertPriority.medium,
        'LOW' => AlertPriority.low,
        _ => AlertPriority.medium,
      };

      // Build the combined list of all media: attached files + optional audio
      // The voice note is NOT in here. It goes as `voiceNote:` below, into its
      // own column, so the screens that read it can say whose voice it is.
      final allMediaFiles = [..._attachedFiles];

      // submitAlert handles its own Cloudinary upload for instant-submit path
      final attachmentPaths = allMediaFiles.map((f) => f.path).toList();

      final alertId = await ref.read(alertServiceProvider).submitAlert(
            type: '${widget.categoryInfo.label} - ${widget.subType}',
            description: desc,
            reportedBy: _anonymous ? 'anonymous' : userId,
            priority: priority,
            latitude: _shareLocation ? lat : null,
            longitude: _shareLocation ? lng : null,
            attachments: attachmentPaths,
            voiceNote: _voiceNote,
            geoLga: _manualOverride ? _selectedLga?.name : null,
            geoWard: _manualOverride ? _selectedWard?.name : null,
            geoSiecWard: _manualOverride ? _selectedSiecWard?.name : null,
            geoPu: _manualOverride ? _selectedPu : null,
            syncStatus: isOffline ? 'QUEUED' : 'COMPLETED',
          );

      // If there are media files that weren't uploaded inline, queue them now.
      // queueMediaUpload now correctly handles List<File> (BUG #15 fix).
      if (alertId != null && allMediaFiles.isNotEmpty) {
        await ref.read(syncServiceProvider).queueMediaUpload(
              alertId: alertId,
              files: allMediaFiles, // Pass File objects directly
              userId: userId,
            );
      }

      if (!mounted) return;

      // Navigate to success/tracking screen instead of silently going home
      try {
        context.go(
          AppRoutes.reportSuccess,
          extra: {
            'alertId': alertId ?? '',
            // The OUTCOME, not the pre-flight radio reading. `isOffline` above
            // is still used to choose the queue's syncStatus, where a guess is
            // fine; what the person is told must come from what actually
            // happened. See AlertService.wasQueuedOffline.
            'isOffline': AlertService.wasQueuedOffline(alertId),
            'type': '${widget.categoryInfo.label} - ${widget.subType}',
          },
        );
      } catch (navErr) {
        debugPrint('[REPORT_NAV] GoRouter not in context (test environment): $navErr');
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint('[REPORT_FATAL] Transmission failed: $e');
      if (mounted) {
        final lang = ref.read(languageProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${Translations.get('rpt_transmission_error', lang)}: $e'),
            backgroundColor: AppColors.emergency,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final cat = widget.categoryInfo;
    final locAsync = ref.watch(userLocationStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: RainbowAppBar(
        title: Translations.get('rpt_incident_dossier', lang),
        subtitle: Translations.get('rpt_compile_tactical_data', lang),
        showBack: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Summary banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(20),
              border: Border(left: BorderSide(color: cat.color, width: 6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Translations.get('rpt_transmitting_for', lang),
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: cat.color.withValues(alpha: 0.7),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.subType.toUpperCase(),
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: AppColors.onBackground,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  cat.label.toUpperCase(),
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDim,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Narrative
          _SectionLabel(Translations.get('rpt_mission_narrative', lang)),
          const SizedBox(height: 12),
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isRecording 
                  ? AppColors.emergency.withValues(alpha: 0.05) 
                  : Colors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isRecording ? AppColors.emergency : AppColors.outline,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isRecording
                          ? Translations.get('rpt_recording_voice', lang)
                          : Translations.get('rpt_voice_optional', lang),
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: _isRecording ? AppColors.emergency : AppColors.primary,
                        letterSpacing: 1,
                      ),
                    ),
                    if (_recordedAudioPath != null)
                      IconButton(
                        tooltip: Translations.get('rpt_delete_recording', lang),
                        icon: const Icon(Icons.delete_forever_rounded, color: AppColors.emergency, size: 18),
                        onPressed: _deleteRecording,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (_isRecording) ...[
                      const Icon(Icons.fiber_manual_record_rounded, color: AppColors.emergency, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        Translations.get('rpt_speak_now_stop', lang),
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDim,
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.emergency,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.stop_rounded, size: 14),
                        label: Text(Translations.get('rpt_stop', lang), style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900)),
                        onPressed: _stopRecording,
                      ),
                    ] else if (_recordedAudioPath != null) ...[
                      const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          Translations.get('rpt_voice_attached', lang),
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                    ] else ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surfaceContainer,
                          foregroundColor: AppColors.onBackground,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: AppColors.outline),
                          ),
                        ),
                        icon: const Icon(Icons.mic_none_rounded, size: 14, color: AppColors.primary),
                        label: Text(Translations.get('rpt_record_voice_report', lang), style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                        onPressed: _startRecording,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.outline),
            ),
            child: TextField(
              controller: _narrativeCtrl,
              maxLines: 6,
              decoration: InputDecoration(
                hintText:
                    Translations.get('rpt_enter_details_hint', lang),
                hintStyle:
                    GoogleFonts.outfit(color: AppColors.textDim, fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(20),
              ),
              style: GoogleFonts.outfit(
                fontSize: 14,
                height: 1.6,
                color: AppColors.onBackground,
                fontWeight: FontWeight.w500,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${_narrativeCtrl.text.length} CHARS / MISSION_LOG_SENSITIVE',
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDim,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Media attachment
          _SectionLabel(Translations.get('rpt_visual_telemetry', lang)),
          const SizedBox(height: 12),
          Row(
            children: [
              _MediaBtn(
                icon: Icons.camera_alt_rounded,
                label: Translations.get('rpt_scan_photo', lang),
                onTap: _takePhoto,
              ),
              const SizedBox(width: 8),
              _MediaBtn(
                icon: Icons.videocam_rounded,
                label: Translations.get('rpt_record_video', lang),
                onTap: _takeVideo,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _MediaBtn(
                icon: Icons.photo_library_rounded,
                label: Translations.get('rpt_photo_intel', lang),
                onTap: _pickImage,
              ),
              const SizedBox(width: 8),
              _MediaBtn(
                icon: Icons.video_library_rounded,
                label: Translations.get('rpt_video_intel', lang),
                onTap: _pickVideo,
              ),
            ],
          ),

          // Attached files preview
          if (_attachedFiles.isNotEmpty) ...[
            const SizedBox(height: 16),
            ..._attachedFiles.map(
              (f) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.description_rounded,
                      color: AppColors.primary.withValues(alpha: 0.5),
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        f.path.split('/').last,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _attachedFiles.remove(f)),
                      child: const Icon(
                        Icons.close_rounded,
                        color: AppColors.danger,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Location
          _SectionLabel(Translations.get('rpt_geospatial_coords', lang)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _shareLocation
                    ? AppColors.primary.withValues(alpha: 0.3)
                    : AppColors.outline,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Translations.get('rpt_gps_telemetry', lang),
                        style: GoogleFonts.outfit(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: _shareLocation
                              ? AppColors.primary
                              : AppColors.textDim,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      locAsync.when(
                        data: (pos) {
                          if (pos == null) {
                            return Text(
                              Translations.get('rpt_gps_unavailable', lang),
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: AppColors.warning,
                              ),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                Translations.get('rpt_active_beacon', lang),
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  color: AppColors.onBackground,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                '${pos.latitude.toStringAsFixed(6)} N | ${pos.longitude.toStringAsFixed(6)} E',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          );
                        },
                        loading: () => Text(
                          Translations.get('rpt_acquiring_signal', lang),
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                        ),
                        error: (_, __) => Text(
                          Translations.get('rpt_signal_interrupted', lang),
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _shareLocation,
                  onChanged: (v) => setState(() => _shareLocation = v),
                  activeThumbColor: AppColors.primary,
                  activeTrackColor: AppColors.primary.withValues(alpha: 0.2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Manual Override
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _manualOverride
                    ? AppColors.primary.withValues(alpha: 0.3)
                    : AppColors.outline,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Translations.get('rpt_jurisdiction_override', lang),
                            style: GoogleFonts.outfit(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: _manualOverride
                                  ? AppColors.primary
                                  : AppColors.textDim,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            Translations.get('rpt_manual_location_entry', lang),
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: AppColors.onBackground,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            Translations.get('rpt_use_if_gps_weak', lang),
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              color: AppColors.textDim,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _manualOverride,
                      onChanged: (v) => setState(() => _manualOverride = v),
                      activeThumbColor: AppColors.primary,
                      activeTrackColor:
                          AppColors.primary.withValues(alpha: 0.2),
                    ),
                  ],
                ),
                if (_manualOverride) ...[
                  const SizedBox(height: 20),
                  const Divider(color: AppColors.outline),
                  const SizedBox(height: 20),

                  // LGA Dropdown
                  _DropdownSection(
                    label: Translations.get('rpt_lga', lang),
                    value: _selectedLga?.name,
                    items: plateauTacticalMap.map((lga) => lga.name).toList(),
                    hintText: Translations.get('rpt_select_placeholder', lang),
                    onChanged: (val) {
                      setState(() {
                        _selectedLga = plateauTacticalMap
                                .firstWhereOrNull((lga) => lga.name == val) ??
                            _selectedLga;
                        _selectedWard = null;
                        _selectedPu = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Ward Dropdown
                  _DropdownSection(
                    label: Translations.get('rpt_federal_ward', lang),
                    value: _selectedWard?.name,
                    items:
                        _selectedLga?.wards.map((w) => w.name).toList() ?? [],
                    hintText: Translations.get('rpt_select_placeholder', lang),
                    onChanged: (val) {
                      setState(() {
                        _selectedWard = _selectedLga?.wards
                                .firstWhereOrNull((w) => w.name == val) ??
                            _selectedWard;
                        _selectedPu = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  _DropdownSection(
                    label: Translations.get('rpt_state_ward', lang),
                    value: _selectedSiecWard?.name,
                    items: (_selectedLga?.siecWards.isNotEmpty ?? false)
                        ? _selectedLga!.siecWards.map((w) => w.name).toList()
                        : [Translations.get('not_available', lang)],
                    hintText: Translations.get('rpt_select_placeholder', lang),
                    onChanged: (val) {
                      if (val == Translations.get('not_available', lang)) return;
                      setState(() {
                        _selectedSiecWard = _selectedLga?.siecWards
                                .firstWhereOrNull((w) => w.name == val) ??
                            _selectedSiecWard;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // PU Dropdown
                  _DropdownSection(
                    label: Translations.get('rpt_polling_unit', lang),
                    value: _selectedPu,
                    items: _selectedWard?.pollingUnits ?? [],
                    hintText: Translations.get('rpt_select_placeholder', lang),
                    onChanged: (val) => setState(() => _selectedPu = val),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Anonymous toggle
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.security_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Translations.get('rpt_stealth_mode', lang),
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: AppColors.onBackground,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        Translations.get('rpt_encrypt_identity', lang),
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          color: AppColors.textDim,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _anonymous,
                  onChanged: (v) => setState(() => _anonymous = v),
                  activeThumbColor: AppColors.primary,
                  activeTrackColor: AppColors.primary.withValues(alpha: 0.2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.black.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          Translations.get('rpt_initiate_transmission', lang),
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.bolt_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              Translations.get('rpt_aes_encrypted_tunnel', lang),
              style: GoogleFonts.outfit(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: AppColors.textDim,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}

class _DropdownSection extends StatelessWidget {
  const _DropdownSection({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hintText,
  });
  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 8,
              fontWeight: FontWeight.w900,
              color: AppColors.textDim,
              letterSpacing: 1.5,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.outline),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              items: items
                  .map(
                    (i) => DropdownMenuItem(
                      value: i,
                      child: Text(
                        i,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: AppColors.onBackground,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
              dropdownColor: AppColors.background,
              isExpanded: true,
              hint: hintText != null
                  ? Text(
                      hintText!,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: AppColors.textDim,
                      ),
                    )
                  : null,
              icon: const Icon(
                Icons.arrow_drop_down_rounded,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: AppColors.textDim,
          letterSpacing: 2,
        ),
      );
}

class _MediaBtn extends StatelessWidget {
  const _MediaBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 80,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.outline),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: AppColors.primary, size: 24),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textSecondary,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
