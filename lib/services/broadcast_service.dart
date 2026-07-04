// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/core/models/broadcast_alert.dart';
import 'package:rainbow_app/providers/auth_provider.dart';

/// Documentation for this public member.

final broadcastProvider = StreamProvider<List<BroadcastAlert>>((ref) {
  final auth = ref.watch(authProvider);
  if (auth.user == null) return Stream.value([]);

  final lga = auth.profile?['geo_lga'] as String?;
  final ward = auth.profile?['geo_ward'] as String?;

  return FirebaseFirestore.instance
      .collection('broadcast_alerts')
      .where('active', isEqualTo: true)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) {
    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return BroadcastAlert.fromJson(data);
    }).where((alert) {
      // 1. Audience filtering
      if (alert.targetAudience != 'ALL') {
        if (alert.targetAudience == 'STAFF' &&
            auth.role != UserRole.responder) {
          return false;
        }
        if (alert.targetAudience == 'USER' && auth.role != UserRole.citizen) {
          return false;
        }
      }

      // 2. Segment filtering (if specified in custom data or similar)
      // In this system, we can use targetLga/targetWard for jurisdictional filtering

      if (alert.targetLga != null && alert.targetLga != lga) return false;
      if (alert.targetWard != null && alert.targetWard != ward) return false;

      return true;
    }).toList();
  });
});
