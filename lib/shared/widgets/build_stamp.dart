import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/app_colors.dart';

/// The build's own identity, small, at the foot of the sign-in screen.
///
/// Three separate times in one week a fix was reported as "still broken" from
/// a handset that was running the build from before the fix — "the same old
/// app was compiled why?", "the app logo is showing the old logo", and a
/// screenshot of a message that the commit an hour earlier had deleted. Each
/// one cost a round of diagnosis of code that was already correct, because
/// neither end could tell which build was on the phone.
///
/// The sign-in screen is the one screen everybody reaches, including somebody
/// who cannot get past it, so the version goes here. It is the first thing to
/// read out when a screen does not match what the code says it should.
///
/// [resolve] exists for tests. `PackageInfo.fromPlatform()` needs the plugin
/// registered, which a widget test does not have; it throws there, the stamp
/// renders nothing, and the screen under test is unaffected.
class BuildStamp extends StatefulWidget {
  const BuildStamp({super.key, this.resolve});

  final Future<String?> Function()? resolve;

  @override
  State<BuildStamp> createState() => _BuildStampState();
}

class _BuildStampState extends State<BuildStamp> {
  String? _stamp;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    final read = widget.resolve ?? _fromPlatform;
    String? stamp;
    try {
      stamp = await read();
    } catch (_) {
      stamp = null;
    }
    if (mounted) {
      setState(() => _stamp = stamp);
    }
  }

  static Future<String?> _fromPlatform() async {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isEmpty) {
      return null;
    }
    return 'v${info.version} (${info.buildNumber})';
  }

  @override
  Widget build(BuildContext context) {
    final stamp = _stamp;
    if (stamp == null) {
      return const SizedBox.shrink();
    }
    return Text(
      stamp,
      textAlign: TextAlign.center,
      style: GoogleFonts.outfit(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w600,
        fontSize: 11,
        letterSpacing: 1.2,
      ),
    );
  }
}
