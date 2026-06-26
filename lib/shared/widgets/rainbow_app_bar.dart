import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';

/// Documentation for this public member.

class RainbowAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Documentation for this public member.
  const RainbowAppBar({
    required this.title,
    super.key,
    this.subtitle,
    this.actions,
    this.showBack = false,
  });

  /// Documentation for this public member.
  final String title;

  /// Documentation for this public member.
  final String? subtitle;

  /// Documentation for this public member.
  final List<Widget>? actions;

  /// Documentation for this public member.
  final bool showBack;

  @override
  Size get preferredSize => const Size.fromHeight(80);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          bottom: BorderSide(color: AppColors.outline),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(
            children: [
              if (showBack)
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 44,
                    height: 44,
                    margin: const EdgeInsets.only(right: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.outline),
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: AppColors.onBackground,
                      size: 16,
                    ),
                  ),
                )
              else
                Builder(
                  builder: (context) {
                    return GestureDetector(
                      onTap: () {
                        var state = Scaffold.maybeOf(context);
                        if (state != null && !state.hasDrawer) {
                          final parent = Scaffold.maybeOf(state.context);
                          if (parent != null) state = parent;
                        }
                        state?.openDrawer();
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        margin: const EdgeInsets.only(right: 16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainer,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.outline),
                        ),
                        child: const Icon(
                          Icons.menu_rounded,
                          color: AppColors.onBackground,
                          size: 20,
                        ),
                      ),
                    );
                  },
                ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.1),
                  ),
                ),
                child: const Icon(
                  Icons.radar_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title.toUpperCase(),
                      style: GoogleFonts.outfit(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 1,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!.toUpperCase(),
                          style: GoogleFonts.outfit(
                            color: AppColors.textDim,
                            fontWeight: FontWeight.w800,
                            fontSize: 9,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (actions != null) ...actions!,
            ],
          ),
        ),
      ),
    );
  }
}
