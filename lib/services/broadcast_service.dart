import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/core/models/broadcast_alert.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/providers/auth_provider.dart';

final broadcastProvider = StreamProvider<List<BroadcastAlert>>((ref) {
  final auth = ref.watch(authProvider);
  if (auth.user == null) return Stream.value([]);

  return SupabaseConfig.client
      .from('system_alerts')
      .stream(primaryKey: ['id'])
      .map((data) {
    return data.map((d) {
      return BroadcastAlert(
        id: d['id'] as String? ?? '',
        message: d['message'] as String? ?? '',
        severity: d['severity'] as String? ?? 'MEDIUM',
        targetAudience: d['target_audience'] as String? ?? 'ALL',
        createdAt: DateTime.tryParse(d['created_at'] as String? ?? '') ?? DateTime.now(),
        expiresAt: DateTime.tryParse(d['expires_at'] as String? ?? '') ?? DateTime.now().add(const Duration(hours: 24)),
      );
    }).where((alert) => alert.expiresAt == null || alert.expiresAt!.isAfter(DateTime.now())).toList();
  });
});
