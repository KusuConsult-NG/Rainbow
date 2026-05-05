import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';
import '../../services/device_service.dart';

class AgentLoginScreen extends StatefulWidget {
  final String roleId;
  const AgentLoginScreen({super.key, required this.roleId});

  @override
  State<AgentLoginScreen> createState() => _AgentLoginScreenState();
}

class _AgentLoginScreenState extends State<AgentLoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) return;
    setState(() => _loading = true);

    try {
      final badgeId = _usernameController.text.trim().toLowerCase();
      final pin = _passwordController.text;
      
      final emailDomain = badgeId.contains('@') ? '' : '@operationrainbow.plateau.gov.ng';
      final formattedEmail = '$badgeId$emailDomain';
      
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: formattedEmail,
        password: pin,
      );

      // PRD §5 + §14: Device binding — register device fingerprint to user profile
      if (cred.user != null) {
        await DeviceService().registerDeviceSession(cred.user!.uid);
        // PRD §5: Listen for HQ forced-logout signal
        DeviceService().listenForForcedLogout(cred.user!.uid, () {
          if (mounted) context.go(AppRoutes.login);
        });
      }

      if (mounted) {
        setState(() => _loading = false);
        context.go(AppRoutes.agentDashboard, extra: widget.roleId);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String get _roleName {
    switch (widget.roleId) {
      case 'POLLING_UNIT': return 'Polling Unit Officer';
      case 'WARD_OFFICER': return 'Ward Officer';
      case 'LGA_OFFICER': return 'LGA Officer';
      case 'HQ_OFFICER': return 'HQ Officer';
      default: return 'Agent';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 80),
                    const SizedBox(height: 16),
                    Text(
                      'AGENT PORTAL',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(51),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _roleName,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Secure Login',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enter your staff credentials to continue',
                    style: GoogleFonts.inter(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _usernameController,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Username or Staff ID',
                      filled: true,
                      fillColor: AppColors.surfaceContainerLow,
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: AppColors.primary, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Password',
                      filled: true,
                      fillColor: AppColors.surfaceContainerLow,
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: AppColors.primary, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _login,
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              'LOGIN',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                letterSpacing: 1.5,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
