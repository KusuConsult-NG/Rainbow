// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:rainbow_app/core/constants/alert_categories.dart';
import 'package:rainbow_app/core/constants/tactical_mapping.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/models/alert_model.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/speech_service.dart';
import 'package:rainbow_app/services/auth_service.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/services/sync_service.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';

/// Documentation for this public member.

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
  final ImagePicker _picker = ImagePicker();

  final _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordedAudioPath;

  Future<void> _pickImage() async {
    final image =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      setState(() => _attachedFiles.add(File(image.path)));
    }
  }

  Future<void> _takePhoto() async {
    final photo =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (photo != null) {
      setState(() => _attachedFiles.add(File(photo.path)));
    }
  }

  Future<void> _pickVideo() async {
    final video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video != null) {
      setState(() => _attachedFiles.add(File(video.path)));
    }
  }

  Future<void> _takeVideo() async {
    final video = await _picker.pickVideo(source: ImageSource.camera);
    if (video != null) {
      setState(() => _attachedFiles.add(File(video.path)));
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/audio_report_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
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
        });
      }
    } catch (e) {
      debugPrint('[AUDIO_REC] Start failed: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      await SpeechService.instance.stopListening();
      if (path != null) {
        final file = File(path);
        setState(() {
          _isRecording = false;
          _recordedAudioPath = path;
          _attachedFiles.add(file);
          if (_narrativeCtrl.text.isEmpty || _narrativeCtrl.text == '[AUDIO_REPORT] voice message recorded') {
            _narrativeCtrl.text = '[AUDIO_REPORT] voice message recorded';
          }
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
        _narrativeCtrl.clear();
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
      final userId = ref.read(authServiceProvider).currentUserId ?? 'anonymous';
      final desc = _narrativeCtrl.text.isEmpty
          ? 'No narrative provided'
          : _narrativeCtrl.text;

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

      final mediaPaths = _attachedFiles.map((f) => f.path).toList();
      if (_recordedAudioPath != null && !mediaPaths.contains(_recordedAudioPath)) {
        mediaPaths.add(_recordedAudioPath!);
      }

      final alertId = await ref.read(alertServiceProvider).submitAlert(
            type: '${widget.categoryInfo.label} - ${widget.subType}',
            description: desc,
            reportedBy: _anonymous ? 'anonymous' : userId,
            priority: priority,
            latitude: _shareLocation ? lat : null,
            longitude: _shareLocation ? lng : null,
            attachments: mediaPaths,
            geoLga: _manualOverride ? _selectedLga?.name : null,
            geoWard: _manualOverride ? _selectedWard?.name : null,
            geoSiecWard: _manualOverride ? _selectedSiecWard?.name : null,
            geoPu: _manualOverride ? _selectedPu : null,
            syncStatus: isOffline ? 'QUEUED' : 'COMPLETED',
          );

      if (alertId != null && _attachedFiles.isNotEmpty) {
        await ref.read(syncServiceProvider).queueMediaUpload(
              alertId: alertId,
              files: _attachedFiles,
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
            'isOffline': isOffline,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('TRANSMISSION ERROR: $e'),
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
    final cat = widget.categoryInfo;
    final locAsync = ref.watch(userLocationStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const RainbowAppBar(
        title: 'INCIDENT DOSSIER',
        subtitle: 'COMPILE TACTICAL DATA',
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
                  'TRANSMITTING REPORT FOR',
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
          const _SectionLabel('MISSION NARRATIVE'),
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
                      _isRecording ? 'RECORDING VOICE REPORT...' : 'VOICE REPORTING (OPTIONAL)',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: _isRecording ? AppColors.emergency : AppColors.primary,
                        letterSpacing: 1,
                      ),
                    ),
                    if (_recordedAudioPath != null)
                      IconButton(
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
                        'SPEAK NOW (TAP STOP TO FINISH)',
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
                        label: Text('STOP', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900)),
                        onPressed: _stopRecording,
                      ),
                    ] else if (_recordedAudioPath != null) ...[
                      const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'VOICE NOTE ATTACHED & ENCRYPTED',
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
                        label: Text('RECORD VOICE REPORT', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
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
                    'Enter mission details, observations, and objective status...',
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
          const _SectionLabel('VISUAL TELEMETRY (OPTIONAL)'),
          const SizedBox(height: 12),
          Row(
            children: [
              _MediaBtn(
                icon: Icons.camera_alt_rounded,
                label: 'SCAN PHOTO',
                onTap: _takePhoto,
              ),
              const SizedBox(width: 8),
              _MediaBtn(
                icon: Icons.videocam_rounded,
                label: 'RECORD VIDEO',
                onTap: _takeVideo,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _MediaBtn(
                icon: Icons.photo_library_rounded,
                label: 'PHOTO INTEL',
                onTap: _pickImage,
              ),
              const SizedBox(width: 8),
              _MediaBtn(
                icon: Icons.video_library_rounded,
                label: 'VIDEO INTEL',
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
                        color: Colors.redAccent,
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
          const _SectionLabel('GEOSPATIAL COORDINATES'),
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
                        'GPS TELEMETRY',
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
                              'GPS UNAVAILABLE',
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
                                'ACTIVE BEACON SIGNAL',
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
                          'ACQUIRING SIGNAL...',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                        ),
                        error: (_, __) => Text(
                          'SIGNAL INTERRUPTED',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Colors.redAccent,
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
                            'JURISDICTION OVERRIDE',
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
                            'MANUAL LOCATION ENTRY',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: AppColors.onBackground,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'USE IF GPS SIGNAL IS WEAK OR INACCURATE',
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
                    label: 'LOCAL GOVERNMENT AREA',
                    value: _selectedLga?.name,
                    items: plateauTacticalMap.map((lga) => lga.name).toList(),
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
                    label: 'FEDERAL WARD (INEC)',
                    value: _selectedWard?.name,
                    items:
                        _selectedLga?.wards.map((w) => w.name).toList() ?? [],
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
                    label: 'STATE WARD (SIEC)',
                    value: _selectedSiecWard?.name,
                    items: (_selectedLga?.siecWards.isNotEmpty ?? false)
                        ? _selectedLga!.siecWards.map((w) => w.name).toList()
                        : ['N/A'],
                    onChanged: (val) {
                      if (val == 'N/A') return;
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
                    label: 'POLLING UNIT (PU)',
                    value: _selectedPu,
                    items: _selectedWard?.pollingUnits ?? [],
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
                        'STEALTH MODE',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: AppColors.onBackground,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'ENCRYPT SENDER IDENTITY ARCHIVE',
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
                          'INITIATE TRANSMISSION',
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
              'AES-256 ENCRYPTED TUNNEL · MISSION CRITICAL DATA',
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
  });
  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

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
              hint: Text(
                'SELECT...',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: AppColors.textDim,
                ),
              ),
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
