import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rainbow_app/core/router/safe_pop.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';

/// Sets the user's safe PIN and duress PIN.
///
/// Four entries — each PIN twice — then one call to `set_emergency_pins`, which
/// hashes both on the server. Nothing entered here is stored on the device.
///
/// Reached from onboarding (after emergency contacts) and from Settings.
class EmergencyPinScreen extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const EmergencyPinScreen({super.key, this.fromOnboarding = false});

  /// When true, finishing goes to the home screen instead of popping.
  final bool fromOnboarding;

  @override
  ConsumerState<EmergencyPinScreen> createState() => _EmergencyPinScreenState();
}

enum _Step { safe, safeConfirm, duress, duressConfirm }

class _EmergencyPinScreenState extends ConsumerState<EmergencyPinScreen> {
  _Step _step = _Step.safe;
  final _controller = TextEditingController();
  String _safe = '';
  String _duress = '';
  String? _error;
  bool _saving = false;

  static final _digits = RegExp(r'^[0-9]{4,8}$');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _title => switch (_step) {
        _Step.safe => 'Choose your SAFE PIN',
        _Step.safeConfirm => 'Confirm your SAFE PIN',
        _Step.duress => 'Choose your DURESS PIN',
        _Step.duressConfirm => 'Confirm your DURESS PIN',
      };

  String get _hint => switch (_step) {
        _Step.safe => 'Enter this to cancel an SOS normally. 4–8 digits.',
        _Step.safeConfirm => 'Enter the same PIN again.',
        _Step.duress =>
          'Enter this if you are forced to cancel. The screen will look '
              'normal, but HQ will be told you are in danger. Must differ from '
              'your safe PIN.',
        _Step.duressConfirm => 'Enter the same PIN again.',
      };

  Future<void> _next() async {
    final value = _controller.text.trim();
    setState(() => _error = null);

    switch (_step) {
      case _Step.safe:
        if (!_digits.hasMatch(value)) {
          setState(() => _error = 'Use 4 to 8 digits.');
          return;
        }
        _safe = value;
        _advance(_Step.safeConfirm);
      case _Step.safeConfirm:
        if (value != _safe) {
          setState(() => _error = 'The PINs do not match. Try again.');
          _controller.clear();
          return;
        }
        _advance(_Step.duress);
      case _Step.duress:
        if (!_digits.hasMatch(value)) {
          setState(() => _error = 'Use 4 to 8 digits.');
          return;
        }
        if (value == _safe) {
          setState(() => _error = 'The duress PIN must be different from the safe PIN.');
          return;
        }
        _duress = value;
        _advance(_Step.duressConfirm);
      case _Step.duressConfirm:
        if (value != _duress) {
          setState(() => _error = 'The PINs do not match. Try again.');
          _controller.clear();
          return;
        }
        await _save();
    }
  }

  void _advance(_Step to) {
    unawaited(HapticFeedback.lightImpact());
    _controller.clear();
    setState(() => _step = to);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await SupabaseConfig.client.rpc<dynamic>(
        'set_emergency_pins',
        params: <String, dynamic>{'p_safe': _safe, 'p_duress': _duress},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emergency PINs saved.')),
      );
      if (widget.fromOnboarding) {
        context.go(AppRoutes.home);
      } else {
        // The PIN is already saved; see mission_resolution_screen.
        context.popOrGo(AppRoutes.settings);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save PINs — check your connection and try again.';
      });
    } finally {
      // Never keep either PIN around longer than the call that consumed it.
      _safe = '';
      _duress = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: !widget.fromOnboarding,
        title: Text(
          'EMERGENCY PIN',
          style: GoogleFonts.outfit(
            color: AppColors.onBackground,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            fontSize: 14,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Step ${_step.index + 1} of 4',
                style: GoogleFonts.inter(color: AppColors.textDim, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Text(
                _title,
                style: GoogleFonts.outfit(
                  color: AppColors.onBackground,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _hint,
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                key: const ValueKey('pin-field'),
                controller: _controller,
                autofocus: true,
                obscureText: true,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  letterSpacing: 12,
                  color: AppColors.onBackground,
                ),
                onSubmitted: (_) => _next(),
                decoration: InputDecoration(
                  errorText: _error,
                  filled: true,
                  fillColor: AppColors.surfaceContainer,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const Spacer(),
              ElevatedButton(
                key: const ValueKey('pin-continue'),
                onPressed: _saving ? null : _next,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emergency,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _step == _Step.duressConfirm ? 'SAVE PINS' : 'CONTINUE',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
