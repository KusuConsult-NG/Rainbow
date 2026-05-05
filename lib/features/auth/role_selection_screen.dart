import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> with SingleTickerProviderStateMixin {
  late AnimationController _shieldController;
  bool _showAgentCategories = false;

  @override
  void initState() {
    super.initState();
    _shieldController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shieldController.dispose();
    super.dispose();
  }

  void _onCitizenSelected() {
    context.push(AppRoutes.login);
  }

  void _onAgentCategorySelected(String role) {
    // Navigate to Agent Login with the selected role
    context.push(AppRoutes.agentLogin, extra: role);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: SafeArea(
        child: Column(
          children: [
            // Header visual
            Expanded(
              flex: 2,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Background glow
                  AnimatedBuilder(
                    animation: _shieldController,
                    builder: (_, __) => Container(
                      width: 280 + _shieldController.value * 30,
                      height: 280 + _shieldController.value * 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withAlpha((_shieldController.value * 15).toInt()),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield_rounded, color: Colors.white, size: 100),
                      const SizedBox(height: 16),
                      Text(
                        'OPERATION RAINBOW',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'PLATEAU STATE EMERGENCY RESPONSE',
                        style: GoogleFonts.inter(
                          color: Colors.white60,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Selection card
            Container(
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Select Your Role',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose how you are accessing the system',
                    style: GoogleFonts.inter(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (!_showAgentCategories) ...[
                    _buildRoleCard(
                      title: 'Citizen',
                      subtitle: 'Report incidents and send emergency alerts',
                      icon: Icons.person_rounded,
                      onTap: _onCitizenSelected,
                    ),
                    const SizedBox(height: 16),
                    _buildRoleCard(
                      title: 'Field Agent',
                      subtitle: 'Respond to alerts and manage operations',
                      icon: Icons.admin_panel_settings_rounded,
                      onTap: () {
                        setState(() {
                          _showAgentCategories = true;
                        });
                      },
                    ),
                  ] else ...[
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () {
                            setState(() {
                              _showAgentCategories = false;
                            });
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Select Agent Category',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildCategoryCard('Polling Unit Officer', 'POLLING_UNIT'),
                    const SizedBox(height: 12),
                    _buildCategoryCard('Ward Officer', 'WARD_OFFICER'),
                    const SizedBox(height: 12),
                    _buildCategoryCard('LGA Officer', 'LGA_OFFICER'),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }

  Widget _buildRoleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outlineVariant.withAlpha(128)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.outline),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard(String title, String roleId) {
    return InkWell(
      onTap: () => _onAgentCategorySelected(roleId),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          children: [
            const Icon(Icons.badge_outlined, color: AppColors.primary, size: 20),
            const SizedBox(width: 12),
            Text(
              title,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.outline),
          ],
        ),
      ),
    );
  }
}
