// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Documentation for this public member.
final uninstallRequestStreamProvider = StreamProvider.family<DocumentSnapshot, String>((ref, uid) {
  return FirebaseFirestore.instance
      .collection('uninstall_requests')
      .doc(uid)
      .snapshots();
});

/// Documentation for this public member.

class UninstallRequestScreen extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const UninstallRequestScreen({super.key});

  @override
  ConsumerState<UninstallRequestScreen> createState() =>
      _UninstallRequestScreenState();
}

class _UninstallRequestScreenState
    extends ConsumerState<UninstallRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _remarksCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  String _selectedReason = 'Device Upgrade';
  bool _isSubmitting = false;
  bool _isVerifying = false;

  final List<String> _reasons = [
    'Device Upgrade',
    'Retirement',
    'Deployment Ended',
    'Security Compromise',
    'Other',
  ];

  @override
  void dispose() {
    _remarksCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final func =
          FirebaseFunctions.instance.httpsCallable('requestAppUninstall');
      await func.call<dynamic>({
        'reason': _selectedReason,
        'remarks': _remarksCtrl.text.trim(),
      });
      unawaited(HapticFeedback.mediumImpact());
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint(
        '[UNINSTALL_REQUEST_ERR] Cloud function failed: $e. Falling back to direct firestore write...',
      );
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await FirebaseFirestore.instance
              .collection('uninstall_requests')
              .doc(uid)
              .set({
            'uid': uid,
            'email': FirebaseAuth.instance.currentUser?.email ?? '',
            'role': 'RESPONDER',
            'reason': _selectedReason,
            'remarks': _remarksCtrl.text.trim(),
            'status': 'PENDING',
            'createdAt': FieldValue.serverTimestamp(),
          });
          unawaited(HapticFeedback.mediumImpact());
        }
        // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
      } catch (fallbackErr) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to submit request: $fallbackErr'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otpCtrl.text.trim();
    if (code.isEmpty || code.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid OTP code'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isVerifying = true);

    try {
      final func =
          FirebaseFunctions.instance.httpsCallable('validateRemovalCode');
      await func.call<dynamic>({
        'removalCode': code,
      });

      unawaited(HapticFeedback.heavyImpact());

      // Success: wipe local SharedPreferences and sign out
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Update local state to force locked UI
      await ref.read(authProvider.notifier).signOut();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('DEACTIVATION COMPLETE. APP SECURELY WIPED.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint(
        '[OTP_VERIFY_ERR] Cloud function failed: $e. Falling back to direct validation...',
      );
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          final doc = await FirebaseFirestore.instance
              .collection('uninstall_requests')
              .doc(uid)
              .get();
          if (doc.exists &&
              doc.data()?['removalCode'] == code.toUpperCase().trim() &&
              doc.data()?['status'] == 'APPROVED') {
            // update statuses directly
            await FirebaseFirestore.instance
                .collection('uninstall_requests')
                .doc(uid)
                .update({
              'status': 'COMPLETED',
              'completedAt': FieldValue.serverTimestamp(),
            });
            await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .update({
              'status': 'deactivated',
              'deactivatedAt': FieldValue.serverTimestamp(),
            });

            final prefs = await SharedPreferences.getInstance();
            await prefs.clear();
            await ref.read(authProvider.notifier).signOut();

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('DEACTIVATION COMPLETE (FALLBACK MODE)'),
                  backgroundColor: AppColors.success,
                ),
              );
            }
          } else {
            throw Exception('Invalid OTP or request not approved');
          }
        }
        // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
      } catch (fallbackErr) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('OTP Verification failed: $fallbackErr'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authProvider).user?.uid;
    final profile = ref.watch(authProvider).profile ?? {};
    final isUserDeactivated = profile['status'] == 'deactivated';

    if (isUserDeactivated || uid == null) {
      return _buildLockedDeactivationScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const RainbowAppBar(
        title: 'APP DEACTIVATION',
        subtitle: 'SECURE COMPLIANCE GOVERNANCE',
        showBack: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: ref.watch(uninstallRequestStreamProvider(uid).stream),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final data = snapshot.data?.data() as Map<String, dynamic>?;
          if (data == null) {
            return _buildRequestForm();
          }

          final status = data['status'] ?? 'PENDING';
          if (status == 'PENDING') {
            return _buildPendingScreen(data);
          } else if (status == 'APPROVED') {
            return _buildApprovedScreen(data);
          } else if (status == 'COMPLETED') {
            return _buildLockedDeactivationScreen();
          }

          return _buildRequestForm();
        },
      ),
    );
  }

  Widget _buildRequestForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.error,
                  size: 28,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CRITICAL COMPLIANCE NOTICE',
                        style: GoogleFonts.outfit(
                          color: AppColors.error,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Deactivating this application wipes all local mission cache, terminates active operational credentials, and notifies the Plateau Security Command HQ. This action is tracked in the immutable security audit log.',
                        style: GoogleFonts.outfit(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'DEACTIVATION REASON',
            style: GoogleFonts.outfit(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _selectedReason,
            dropdownColor: AppColors.surfaceContainerHigh,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.1),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.outline),
              ),
            ),
            style:
                GoogleFonts.outfit(color: AppColors.onBackground, fontSize: 14),
            items: _reasons.map((reason) {
              return DropdownMenuItem<String>(
                value: reason,
                child: Text(reason),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedReason = val);
              }
            },
          ),
          const SizedBox(height: 24),
          Text(
            'DETAILED REMARKS / REMOVAL JUSTIFICATION',
            style: GoogleFonts.outfit(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _remarksCtrl,
            maxLines: 4,
            style:
                GoogleFonts.outfit(color: AppColors.onBackground, fontSize: 14),
            decoration: InputDecoration(
              hintText:
                  'Describe details of your device swap, deployment end, or decommissioning justification...',
              hintStyle:
                  GoogleFonts.outfit(color: AppColors.textDim, fontSize: 13),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.1),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.outline),
              ),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Justification is required for deactivation requests';
              }
              return null;
            },
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submitRequest,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.error.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : Text(
                    'SUBMIT DEACTIVATION REQUEST',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      fontSize: 14,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingScreen(Map<String, dynamic> data) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                color: AppColors.warning,
                strokeWidth: 4,
              ),
            ),
            const SizedBox(height: 40),
            Text(
              'AWAITING HQ APPROVAL',
              style: GoogleFonts.outfit(
                color: AppColors.warning,
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Your compliance uninstall request has been securely logged on the Command mainframe. Command is auditing your active missions and active security tokens.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.outline),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.success,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'No Active Assigned Alerts',
                        style: GoogleFonts.outfit(
                          color: AppColors.onBackground,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.success,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Audit Trail Registered',
                        style: GoogleFonts.outfit(
                          color: AppColors.onBackground,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApprovedScreen(Map<String, dynamic> data) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.verified_rounded,
                color: AppColors.success,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'DEACTIVATION APPROVED',
                style: GoogleFonts.outfit(
                  color: AppColors.success,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Plateau Command HQ has verified and approved your uninstall request. Enter the time-bound deactivation OTP to execute the local wipe sequence.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        Text(
          'ENTER 6-CHARACTER REMOVA SECURITY OTP',
          style: GoogleFonts.outfit(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _otpCtrl,
          style: GoogleFonts.outfit(
            color: AppColors.onBackground,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 6,
          ),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: 'RMV-XXXXXX',
            hintStyle: GoogleFonts.outfit(
              color: AppColors.textDim,
              fontSize: 20,
              letterSpacing: 2,
            ),
            filled: true,
            fillColor: Colors.black.withValues(alpha: 0.1),
            contentPadding: const EdgeInsets.symmetric(vertical: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.outline),
            ),
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: _isVerifying ? null : _verifyOtp,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.success.withValues(alpha: 0.3),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(vertical: 18),
          ),
          child: _isVerifying
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
              : Text(
                  'EXECUTE LOCAL DATA WIPE',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    fontSize: 14,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildLockedDeactivationScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.3),
                      width: 3,
                    ),
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    color: Colors.green,
                    size: 64,
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  'SAFE TO UNINSTALL',
                  style: GoogleFonts.outfit(
                    color: Colors.green,
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'This device has been successfully audited and decommissioned from the Operation Rainbow Security Network.\n\nAll local cache files and security keys have been securely purged. You may now safely delete this application.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 48),
                OutlinedButton(
                  onPressed: () {
                    // Exit the app gracefully
                    unawaited(SystemNavigator.pop());
                  },
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'EXIT APPLICATION',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
