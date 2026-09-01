import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/models/alert_model.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/speech_service.dart';
import 'package:rainbow_app/shared/localization/translations.dart';

class VoiceReportDialog extends ConsumerStatefulWidget {
  const VoiceReportDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'AI Voice Report',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return const VoiceReportDialog();
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
    );
  }

  @override
  ConsumerState<VoiceReportDialog> createState() => _VoiceReportDialogState();
}

class _VoiceReportDialogState extends ConsumerState<VoiceReportDialog>
    with TickerProviderStateMixin {
  late AnimationController _waveformController;
  late AnimationController _pulseController;
  
  String _transcription = '';
  bool _isListening = false;
  bool _isTriaging = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _waveformController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    unawaited(_startListeningFlow());
  }

  @override
  void dispose() {
    _waveformController.dispose();
    _pulseController.dispose();
    unawaited(SpeechService.instance.stopListening());
    super.dispose();
  }

  String _accumulatedText = '';
  String _currentChunk = '';

  Future<void> _startListeningFlow() async {
    final lang = ref.read(languageProvider);
    setState(() {
      _errorMessage = null;
      _isListening = true;
    });

    final initSuccess = await SpeechService.instance.initialize();
    if (!initSuccess) {
      setState(() {
        _isListening = false;
        _errorMessage = Translations.get('error_initialize', lang);
      });
      return;
    }

    unawaited(_waveformController.repeat(reverse: true));
    unawaited(_pulseController.repeat(reverse: true));

    try {
      await SpeechService.instance.startListening(
        onResult: (text) {
          if (!mounted) return;
          setState(() {
            _currentChunk = text;
            _transcription = _accumulatedText.isEmpty
                ? _currentChunk
                : '$_accumulatedText $_currentChunk';
          });
        },
        onStatusChange: (status) {
          if (!mounted) return;
          if ((status == 'done' || status == 'notListening') && _isListening) {
            if (_currentChunk.isNotEmpty) {
              _accumulatedText = _accumulatedText.isEmpty
                  ? _currentChunk
                  : '$_accumulatedText $_currentChunk';
              _currentChunk = '';
            }
            // Auto-restart listening so user can keep talking
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted && _isListening) {
                unawaited(SpeechService.instance.startListening(
                  onResult: (text) {
                    if (!mounted) return;
                    setState(() {
                      _currentChunk = text;
                      _transcription = _accumulatedText.isEmpty
                          ? _currentChunk
                          : '$_accumulatedText $_currentChunk';
                    });
                  },
                ));
              }
            });
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _errorMessage = 'Error starting recorder: $e';
      });
    }
  }

  Future<void> _stopListeningFlow() async {
    await SpeechService.instance.stopListening();
    _waveformController.stop();
    _pulseController.stop();
    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }
  }

  Future<void> _submitReport() async {
    final lang = ref.read(languageProvider);
    if (_transcription.trim().isEmpty) {
      setState(() {
        _errorMessage = Translations.get('no_voice_input', lang);
      });
      return;
    }

    await _stopListeningFlow();

    setState(() {
      _isTriaging = true;
      _errorMessage = null;
    });

    await HapticFeedback.mediumImpact();

    try {
      final auth = ref.read(authProvider);
      final userId = auth.user?.id ?? 'anonymous';

      // Perform AI Triage Classification on recognized voice transcript
      final lowerText = _transcription.toLowerCase();
      var inferredType = 'INCIDENT - AI Voice Report';
      var inferredPriority = AlertPriority.medium;

      if (lowerText.contains('gun') || lowerText.contains('weapon') || lowerText.contains('shoot') || lowerText.contains('kill') || lowerText.contains('attack') || lowerText.contains('blood')) {
        inferredType = 'CRIME - Active Threat / Weapon';
        inferredPriority = AlertPriority.critical;
      } else if (lowerText.contains('fire') || lowerText.contains('explosion') || lowerText.contains('bomb') || lowerText.contains('burn')) {
        inferredType = 'ENVIRONMENT - Fire / Hazard';
        inferredPriority = AlertPriority.critical;
      } else if (lowerText.contains('suspicious') || lowerText.contains('stranger') || lowerText.contains('loitering') || lowerText.contains('prowler')) {
        inferredType = 'SUSPICIOUS - Activity';
        inferredPriority = AlertPriority.high;
      } else if (lowerText.contains('riot') || lowerText.contains('protest') || lowerText.contains('crowd') || lowerText.contains('block')) {
        inferredType = 'DANGER - Civil Unrest';
        inferredPriority = AlertPriority.high;
      }

      final alertId = await ref.read(alertServiceProvider).submitAlert(
            type: inferredType,
            description: '[AI VOICE TRIAGE] Recognized Speech: "$_transcription"',
            reportedBy: userId,
            priority: inferredPriority,
          );

      if (!mounted) return;

      if (alertId != null) {
        // Report successfully created/queued
        await HapticFeedback.heavyImpact();
        Navigator.of(context).pop(); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Translations.get('success_toast', lang),
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: 1,
              ),
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() {
          _isTriaging = false;
          _errorMessage = 'Triage request failed. Please try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTriaging = false;
        _errorMessage = 'Triage failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Blur backdrop
          Positioned.fill(
            child: GestureDetector(
              onTap: _isTriaging ? null : () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          
          // Central content card
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(36),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title / Brand header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(alpha: 0.08),
                        ),
                        child: const Icon(
                          Icons.radar_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        Translations.get('ai_report', lang),
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // State Visualizer
                  if (_isTriaging) ...[
                    // Triage Processing indicator
                    SizedBox(
                      height: 120,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                            color: AppColors.primary,
                            strokeWidth: 3,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            Translations.get('ai_triaging_incident', lang),
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            Translations.get('classifying_details', lang),
                            style: GoogleFonts.outfit(
                              fontSize: 9,
                              color: AppColors.textDim,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Micro-animated Sound wave visualizer
                    GestureDetector(
                      onTap: _isListening ? _stopListeningFlow : _startListeningFlow,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer ambient pulse
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, _) {
                              final pScale = 1.0 + (_pulseController.value * 0.25);
                              return Container(
                                width: 90 * pScale,
                                height: 90 * pScale,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: (_isListening ? AppColors.primary : AppColors.textDim)
                                      .withValues(alpha: 0.06 * (1 - _pulseController.value)),
                                ),
                              );
                            },
                          ),
                          // Breathing circular mic button
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: _isListening
                                    ? [const Color(0xFFFF1744), const Color(0xFFC2185B)]
                                    : [AppColors.textDim, AppColors.textSecondary],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (_isListening ? AppColors.primary : AppColors.textDim)
                                      .withValues(alpha: 0.3),
                                  blurRadius: 15,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Icon(
                              _isListening ? Icons.mic_rounded : Icons.mic_off_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    Text(
                      _isListening
                          ? Translations.get('listening_speak_now', lang)
                          : Translations.get('tap_to_record_again', lang),
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: _isListening ? AppColors.primary : AppColors.textSecondary,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Transcription view block
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      constraints: const BoxConstraints(minHeight: 100, maxHeight: 150),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.outline),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          _transcription.isEmpty
                              ? (_isListening
                                  ? Translations.get('sample_speech_prompt', lang)
                                  : Translations.get('no_voice_input', lang))
                              : _transcription,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: _transcription.isEmpty ? AppColors.textDim : AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: GoogleFonts.outfit(
                        color: AppColors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),

                  // Actions panel
                  if (!_isTriaging)
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              Translations.get('cancel', lang),
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textSecondary,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _transcription.trim().isEmpty ? null : _submitReport,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: AppColors.outline,
                              disabledForegroundColor: AppColors.textDim,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              Translations.get('submit_report', lang),
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
