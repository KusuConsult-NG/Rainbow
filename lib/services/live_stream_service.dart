// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit, avoid_catches_without_on_clauses, require_trailing_commas, public_member_api_docs, inference_failure_on_collection_literal, inference_failure_on_instance_creation
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Documentation for this public member.
class LiveStreamService {
  /// Documentation for this public member.
  factory LiveStreamService() => _instance;
  LiveStreamService._internal();
  static final LiveStreamService _instance = LiveStreamService._internal();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  RealtimeChannel? _channel;
  bool _isStreaming = false;

  /// Documentation for this public member.
  bool get isStreaming => _isStreaming;

  final Map<String, dynamic> _rtcConfig = <String, dynamic>{
    'iceServers': <Map<String, String>>[
      <String, String>{'urls': 'stun:stun.l.google.com:19302'},
      <String, String>{'urls': 'stun:stun1.l.google.com:19302'},
      <String, String>{'urls': 'stun:stun2.l.google.com:19302'},
    ],
  };

  final Map<String, dynamic> _mediaConstraints = <String, dynamic>{
    'audio': true,
    'video': <String, dynamic>{
      'mandatory': <String, String>{
        'minWidth': '640',
        'minHeight': '480',
        'minFrameRate': '15',
      },
      'facingMode': 'environment',
      'optional': <dynamic>[],
    },
  };

  /// Starts live camera stream and initiates WebRTC offer to HQ.
  Future<bool> startStream(String alertId) async {
    if (_isStreaming) return true;

    try {
      debugPrint('[LIVE_STREAM] Starting video stream for alert: $alertId');

      // 1. Get User Media (Camera & Audio)
      _localStream = await navigator.mediaDevices.getUserMedia(_mediaConstraints);

      // 2. Create Peer Connection
      _peerConnection = await createPeerConnection(_rtcConfig);

      // Add local stream tracks to PeerConnection
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }

      // 3. Connect Supabase Realtime Signalling Channel
      final channelName = 'live-stream-$alertId';
      _channel = SupabaseConfig.client.channel(channelName);

      // Handle ICE Candidates from PeerConnection
      _peerConnection!.onIceCandidate = (candidate) async {
        if (_channel != null) {
          unawaited(
            _channel!.sendBroadcastMessage(
              event: 'signalling',
              payload: <String, dynamic>{
                'type': 'candidate',
                'candidate': candidate.toMap(),
                'sender': 'mobile',
              },
            ),
          );
        }
      };

      // Listen for HQ Signalling Messages (Answer & Candidate)
      _channel!.onBroadcast(
        event: 'signalling',
        callback: (payload) async {
          final sender = payload['sender'] as String?;
          if (sender == 'mobile') return; // ignore own messages

          final type = payload['type'] as String?;
          if (type == 'answer') {
            debugPrint('[LIVE_STREAM] Received Answer from HQ');
            final sdp = payload['sdp'] as String?;
            if (sdp != null && _peerConnection != null) {
              final answer = RTCSessionDescription(sdp, 'answer');
              await _peerConnection!.setRemoteDescription(answer);
            }
          } else if (type == 'candidate') {
            debugPrint('[LIVE_STREAM] Received ICE Candidate from HQ');
            final candidateMap = payload['candidate'] as Map<String, dynamic>?;
            if (candidateMap != null && _peerConnection != null) {
              final candidate = RTCIceCandidate(
                candidateMap['candidate'] as String?,
                candidateMap['sdpMid'] as String?,
                candidateMap['sdpMLineIndex'] as int?,
              );
              await _peerConnection!.addCandidate(candidate);
            }
          }
        },
      );

      _channel!.subscribe();

      // 4. Create and Send Offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      await Future<void>.delayed(const Duration(milliseconds: 300));

      await _channel!.sendBroadcastMessage(
        event: 'signalling',
        payload: <String, dynamic>{
          'type': 'offer',
          'sdp': offer.sdp,
          'sender': 'mobile',
        },
      );

      // A write setting `alerts.has_live_stream` used to sit here, with a
      // matching clear in stopStream. It is not a column in any migration, so
      // both were rejected — and both were wrapped in `catch (_) {}`, so the
      // rejection went nowhere. Nothing read the flag either; the console shows
      // LiveFeedViewer for whichever incident is open. Removed rather than
      // given a column, which would only have made a no-op succeed.
      _isStreaming = true;
      debugPrint('[LIVE_STREAM] Stream initialized and offer broadcasted.');
      return true;
    } catch (e) {
      debugPrint('[LIVE_STREAM_ERR] Failed to start live stream: $e');
      await stopStream();
      return false;
    }
  }

  /// Stops the current live stream and cleans up resources.
  ///
  /// Took an optional `alertId` which, once the dead `has_live_stream` write
  /// was removed, did nothing — while every caller dutifully passed one, making
  /// teardown read as though it were scoped to that alert. It is not: there is
  /// one stream per service instance.
  Future<void> stopStream() async {
    try {
      debugPrint('[LIVE_STREAM] Stopping video stream...');
      _isStreaming = false;

      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          unawaited(track.stop());
        }
        await _localStream!.dispose();
        _localStream = null;
      }

      await _peerConnection?.close();
      await _peerConnection?.dispose();
      _peerConnection = null;

      if (_channel != null) {
        unawaited(
          _channel!.sendBroadcastMessage(
            event: 'signalling',
            payload: <String, dynamic>{'type': 'bye', 'sender': 'mobile'},
          ),
        );
        unawaited(SupabaseConfig.client.removeChannel(_channel!));
        _channel = null;
      }
    } catch (e) {
      debugPrint('[LIVE_STREAM_ERR] Error during stopStream: $e');
    }
  }
}
