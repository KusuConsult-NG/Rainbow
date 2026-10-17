import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/router/app_router.dart';
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

  /// The nearest scaffold above [context] that has a drawer, or null.
  ///
  /// A screen's own scaffold usually has none; the navigation shell around it
  /// does. Walks outwards rather than checking one parent, so a screen nested
  /// one level deeper still finds the shell's drawer.
  static ScaffoldState? _drawerHost(BuildContext context) {
    var state = Scaffold.maybeOf(context);
    while (state != null) {
      if (state.hasDrawer) return state;
      state = Scaffold.maybeOf(state.context);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    void goBack() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.home);
      }
    }

    void openMenu() => _drawerHost(context)?.openDrawer();

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
              // THE LEADING BUTTON: a menu where there is a drawer to open, a
              // way back where there is not.
              //
              // This was always a menu button unless the screen asked for
              // `showBack`. A screen with no drawer anywhere above it — the
              // responder's live-tracking map, reached from the agent
              // dashboard — got a menu button that called openDrawer() on
              // nothing: the control sweep found it doing nothing at all. And
              // neither button had a name, so a screen reader announced an
              // unlabelled button and the sweep could only call it "(icon)".
              if (showBack || _drawerHost(context) == null)
                // `onTap` on the Semantics as well as the detector:
                // excludeSemantics drops the detector's own tap action, and a
                // labelled button with no action is one a screen reader can
                // name but never press.
                Semantics(
                  button: true,
                  label: 'Back',
                  onTap: goBack,
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: goBack,
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
                  ),
                )
              else
                Semantics(
                  button: true,
                  label: 'Open menu',
                  onTap: openMenu,
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: openMenu,
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
                  ),
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
              // Scale the title down to fit rather than letting it clip.
              //
              // At 390px — an ordinary phone, not an edge case — the fixed 16px
              // title left "OPERATION RAINBOW" rendering as "OPERATION RAI…",
              // and worse on the responder dashboard, which carries four action
              // icons. BoxFit.scaleDown only ever shrinks, so wide screens keep
              // the full 16px and narrow ones get the whole name at a smaller
              // size instead of a clipped fragment.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title.toUpperCase(),
                        maxLines: 1,
                        softWrap: false,
                        style: GoogleFonts.outfit(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            subtitle!.toUpperCase(),
                            maxLines: 1,
                            softWrap: false,
                            // textDim (#9E9E9E) reaches only 2.56:1 on the
                            // warm white this bar is painted in, at 9px with
                            // 1.5 letter-spacing — the smallest text in the
                            // app, on fourteen screens. textSecondary is the
                            // same grey family at 5.92:1.
                            style: GoogleFonts.outfit(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w800,
                              fontSize: 9,
                              letterSpacing: 1.5,
                            ),
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
