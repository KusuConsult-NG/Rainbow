import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/core/models/broadcast_alert.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/services/broadcast_targeting.dart';
import 'package:rainbow_app/services/user_service.dart';

/// Live HQ advisories addressed to this user.
///
/// Delivery is decided by [broadcastReaches], which is a pure function and is
/// tested directly — it used to be a `.where()` inline here that read the wrong
/// column for audience and never looked at geography at all. See
/// broadcast_targeting.dart for what that cost.
final broadcastProvider = StreamProvider<List<BroadcastAlert>>((ref) {
  final auth = ref.watch(authProvider);
  if (auth.user == null) return Stream.value([]);

  // The recipient's own geography comes from their profile. It is watched, not
  // read once: a responder reassigned to another LGA mid-shift starts receiving
  // that LGA's advisories without restarting the app.
  // `.valueOrNull`: `AsyncError.value` rethrows. See the note in
  // `shared/widgets/system_alert_listener.dart`.
  final profile = ref.watch(userProfileProvider).valueOrNull;
  final to = BroadcastRecipient(
    isResponder: auth.role == UserRole.responder,
    geoLga: profile?['geo_lga'] as String?,
    geoWard: profile?['geo_ward'] as String?,
    geoPu: profile?['geo_pu'] as String?,
  );

  return SupabaseConfig.client
      .from('system_alerts')
      .stream(primaryKey: ['id'])
      .map((rows) => rows
          .where((row) => broadcastReaches(row, to))
          .map(
            (row) => BroadcastAlert(
              id: row['id'] as String? ?? '',
              message: row['message'] as String? ?? '',
              severity: row['severity'] as String? ?? 'MEDIUM',
              targetAudience: broadcastAudience(row),
              targetLga: row['target_lga'] as String?,
              targetWard: row['target_ward'] as String?,
              targetPu: row['target_pu'] as String?,
              createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
              expiresAt: DateTime.tryParse(row['expires_at'] as String? ?? ''),
            ),
          )
          .toList());
});
