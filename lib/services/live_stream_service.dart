// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit, avoid_catches_without_on_clauses, require_trailing_commas, public_member_api_docs, inference_failure_on_collection_literal, inference_failure_on_instance_creation
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:rainbow_app/core/config/live_stream.dart' as cfg;
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Which signalling message this is: `offer`, `answer`, `candidate` or `bye`.
///
/// IT CANNOT BE CALLED `type`, AND IT WAS.
///
/// `RealtimeChannel.send` does this, in realtime_client 2.11.0 line 778:
///
///     payload['type'] = type.toType();
///
/// It MUTATES the caller's map and overwrites any `type` key with the literal
/// 'broadcast'. This service used `type` as its own discriminator, so every
/// signalling message it sent — the offer, every ICE candidate, the bye —
/// arrived at HQ as `type: 'broadcast'`. The console matches on
/// `payload?.type === 'offer'`, which could never be true.
///
/// So the negotiation could never begin. The phone took the camera and the
/// microphone, created a real peer connection, generated a real offer with real
/// ICE candidates, and told the person "LIVE STREAM BROADCASTING TO HQ" — and
/// HQ received messages it could not read and never answered. Somebody in an
/// emergency believed they were showing HQ what was happening to them, with the
/// camera light on to confirm it, and nobody was receiving anything.
///
/// Nothing could have caught this by reading one side: the mobile code is
/// correct in isolation, the console code is correct in isolation, and the
/// collision lives in a line of the SDK between them.
///
/// `signal` is not a reserved key. The fallback tolerates a peer still sending
/// the old shape, but never accepts the literal 'broadcast' as a kind.
String? signalKind(Map<String, dynamic> body) {
  final signal = body['signal'] as String?;
  if (signal != null && signal.isNotEmpty) return signal;
  final legacy = body['type'] as String?;
  return legacy == 'broadcast' ? null : legacy;
}

/// Whether HQ is actually receiving, as opposed to having been sent an offer.
///
/// THE DIFFERENCE IS THE WHOLE POINT, AND THE SCREEN USED TO SHOW THE WRONG ONE.
///
/// `startStream` returned `true` as soon as it had broadcast the offer. It did
/// not wait for an answer, did not watch ICE, and nothing anywhere registered
/// `onConnectionState`. The screen did:
///
///     final success = await LiveStreamService().startStream(alertId);
///     setState(() => _isLiveStreaming = success);
///     ... success ? '🔴 ${_t('eme_broadcast_live')}' : ...
///
/// so somebody in an emergency saw a red BROADCASTING LIVE TO HQ and the camera
/// light come on, having established nothing at all.
///
/// That is word for word the experience the note at the top of this file
/// describes for the `type`/`broadcast` collision: "Somebody in an emergency
/// believed they were showing HQ what was happening to them, with the camera
/// light on to confirm it, and nobody was receiving anything." The collision was
/// fixed. The thing that made it invisible was not, so the next failure in the
/// chain reproduced it exactly — and there is one, because neither side has a
/// TURN relay and STUN cannot get through carrier NAT.
///
/// `connecting` is the honest state between an offer and a connection, and it
/// may be where this ends up: a stream that never connects stays `connecting`
/// until ICE gives up and reports `failed`. Both are things the person needs to
/// be shown. See E2E_AUDIT_REPORT.md T-96.
enum LiveStreamStatus {
  /// Not streaming, and not trying to.
  idle,

  /// The camera is on and an offer has gone to HQ. Nobody is receiving yet.
  connecting,

  /// The peer connection reports `connected`: HQ is receiving.
  live,

  /// Negotiation or connectivity failed. Nobody is receiving.
  failed,
}

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

  /// Broadcast so the screen can listen without owning the subscription, and
  /// so a late listener is not the reason somebody is told nothing.
  final StreamController<LiveStreamStatus> _statusController =
      StreamController<LiveStreamStatus>.broadcast();
  LiveStreamStatus _status = LiveStreamStatus.idle;

  /// What to tell the person right now.
  Stream<LiveStreamStatus> get statusStream => _statusController.stream;

  /// The current status, for a screen that has just started listening.
  LiveStreamStatus get status => _status;

  /// True from the moment the camera is on, including while still connecting.
  ///
  /// Kept because teardown and the toggle both need "is there a stream to stop"
  /// — which is a different question from "is HQ receiving", and conflating the
  /// two is what put BROADCASTING on screen. Use [status] for anything a person
  /// reads.
  bool get isStreaming => _isStreaming;

  void _setStatus(LiveStreamStatus next) {
    if (_status == next) return;
    _status = next;
    debugPrint('[LIVE_STREAM] status -> ${next.name}');
    if (!_statusController.isClosed) _statusController.add(next);
  }

  /// Read from configuration, not written here.
  ///
  /// It was three public STUN servers as literals, and the console had the same
  /// three as its own literals. STUN discovers an address; it cannot relay. A
  /// handset on mobile data is behind carrier-grade NAT, which is commonly
  /// symmetric, and symmetric NAT on either side defeats hole punching — so
  /// without a TURN server the media has no route and the connection simply
  /// never completes. See lib/core/config/live_stream.dart.
  Map<String, dynamic> get _rtcConfig => <String, dynamic>{
        'iceServers': cfg.iceServers,
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

  /// Opens the camera and offers a stream to HQ.
  ///
  /// Returns whether NEGOTIATION STARTED — the camera is on and an offer has
  /// gone out. It deliberately does NOT mean HQ is receiving, which is a thing
  /// only the peer connection can say and which arrives later or not at all.
  /// Watch [statusStream] for that, and never put a word in front of a person
  /// based on this return value. T-96.
  Future<bool> startStream(String alertId) async {
    if (_isStreaming) return true;

    try {
      debugPrint('[LIVE_STREAM] Starting video stream for alert: $alertId');
      // Said once, here, where somebody reading a field log will see it next to
      // the stream that failed.
      cfg.warnIfNoRelay();
      _setStatus(LiveStreamStatus.connecting);

      // 1. Get User Media (Camera & Audio)
      _localStream = await navigator.mediaDevices.getUserMedia(_mediaConstraints);

      // 2. Create Peer Connection
      _peerConnection = await createPeerConnection(_rtcConfig);

      // THE ONLY THING THAT KNOWS WHETHER HQ IS RECEIVING.
      //
      // Nothing registered this before, so the one authoritative answer to the
      // question the screen was asking went unread.
      _peerConnection!.onConnectionState = (state) {
        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _setStatus(LiveStreamStatus.live);
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
            // Not idle: idle reads as "not trying", and somebody who pressed
            // the button needs to know it did not work.
            _setStatus(LiveStreamStatus.failed);
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            // Recoverable — ICE may restart and come back. Reported as
            // connecting rather than failed so a brief tunnel does not tell
            // somebody their stream is dead when it is about to resume.
            _setStatus(LiveStreamStatus.connecting);
          case RTCPeerConnectionState.RTCPeerConnectionStateNew:
          case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
            _setStatus(LiveStreamStatus.connecting);
        }
      };

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
                'signal': 'candidate',
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
          // The console nests its body under `payload`; this client flattens.
          // Read both rather than assume one.
          final body = payload['payload'] is Map
              ? Map<String, dynamic>.from(payload['payload'] as Map)
              : payload;
          final sender = body['sender'] as String?;
          if (sender == 'mobile') return; // ignore own messages

          final type = signalKind(body);
          if (type == 'answer') {
            debugPrint('[LIVE_STREAM] Received Answer from HQ');
            final sdp = body['sdp'] as String?;
            if (sdp != null && _peerConnection != null) {
              final answer = RTCSessionDescription(sdp, 'answer');
              await _peerConnection!.setRemoteDescription(answer);
            }
          } else if (type == 'candidate') {
            debugPrint('[LIVE_STREAM] Received ICE Candidate from HQ');
            final candidateMap = body['candidate'] as Map<String, dynamic>?;
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
          'signal': 'offer',
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
      // The camera is on and the offer has gone. That is all this means, and
      // the status stays `connecting` until the peer connection says otherwise.
      _isStreaming = true;
      debugPrint(
        '[LIVE_STREAM] Offer broadcast. Nobody is receiving yet — waiting for '
        'the peer connection to report connected.',
      );
      return true;
    } catch (e) {
      debugPrint('[LIVE_STREAM_ERR] Failed to start live stream: $e');
      await stopStream();
      _setStatus(LiveStreamStatus.failed);
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
      _setStatus(LiveStreamStatus.idle);

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
            payload: <String, dynamic>{'signal': 'bye', 'sender': 'mobile'},
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
