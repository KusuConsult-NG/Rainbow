'use client';
import { useState, useEffect, useRef } from 'react';
import { supabase } from '@/lib/supabase';
import { Video, VideoOff, RefreshCw, Radio } from 'lucide-react';

interface Props {
  alertId: string;
}

export default function LiveFeedViewer({ alertId }: Props) {
  const [status, setStatus] = useState<'IDLE' | 'CONNECTING' | 'LIVE' | 'DISCONNECTED'>('IDLE');
  const [error, setError] = useState<string | null>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const pcRef = useRef<RTCPeerConnection | null>(null);
  const channelRef = useRef<any>(null);

  const startListening = () => {
    setStatus('CONNECTING');
    setError(null);

    const rtcConfig: RTCConfiguration = {
      iceServers: [
        { urls: 'stun:stun.l.google.com:19302' },
        { urls: 'stun:stun1.l.google.com:19302' },
        { urls: 'stun:stun2.l.google.com:19302' },
      ],
    };

    try {
      const pc = new RTCPeerConnection(rtcConfig);
      pcRef.current = pc;

      pc.ontrack = (event) => {
        console.log('[LIVE_FEED_HQ] Received Remote Stream Track:', event.streams);
        if (videoRef.current && event.streams[0]) {
          videoRef.current.srcObject = event.streams[0];
          setStatus('LIVE');
        }
      };

      pc.onicecandidate = (event) => {
        if (event.candidate && channelRef.current) {
          channelRef.current.send({
            type: 'broadcast',
            event: 'signalling',
            payload: {
              type: 'candidate',
              candidate: event.candidate.toJSON(),
              sender: 'hq',
            },
          });
        }
      };

      pc.onconnectionstatechange = () => {
        console.log('[LIVE_FEED_HQ] Connection state:', pc.connectionState);
        if (pc.connectionState === 'connected') {
          setStatus('LIVE');
        } else if (pc.connectionState === 'disconnected' || pc.connectionState === 'failed') {
          setStatus('DISCONNECTED');
        }
      };

      const channel = supabase.channel(`live-stream-${alertId}`);
      channelRef.current = channel;

      channel
        .on('broadcast', { event: 'signalling' }, async ({ payload }) => {
          const sender = payload?.sender;
          if (sender === 'hq') return; // ignore self

          const type = payload?.type;
          console.log('[LIVE_FEED_HQ] Received Signalling:', type);

          if (type === 'offer') {
            try {
              const offer = new RTCSessionDescription({ type: 'offer', sdp: payload.sdp });
              await pc.setRemoteDescription(offer);
              const answer = await pc.createAnswer();
              await pc.setLocalDescription(answer);

              channel.send({
                type: 'broadcast',
                event: 'signalling',
                payload: {
                  type: 'answer',
                  sdp: answer.sdp,
                  sender: 'hq',
                },
              });
              setStatus('CONNECTING');
            } catch (err: any) {
              console.error('[LIVE_FEED_HQ] Error handling offer:', err);
              setError(err.message || 'WebRTC handshaking error');
            }
          } else if (type === 'candidate') {
            try {
              if (payload.candidate) {
                await pc.addIceCandidate(new RTCIceCandidate(payload.candidate));
              }
            } catch (err) {
              console.error('[LIVE_FEED_HQ] ICE Error:', err);
            }
          } else if (type === 'bye') {
            setStatus('DISCONNECTED');
          }
        })
        .subscribe();

    } catch (err: any) {
      console.error('[LIVE_FEED_HQ] Stream Init Error:', err);
      setError(err.message || 'Failed to initialize WebRTC');
      setStatus('DISCONNECTED');
    }
  };

  const stopListening = () => {
    if (pcRef.current) {
      pcRef.current.close();
      pcRef.current = null;
    }
    if (channelRef.current) {
      supabase.removeChannel(channelRef.current);
      channelRef.current = null;
    }
    if (videoRef.current) {
      videoRef.current.srcObject = null;
    }
    setStatus('IDLE');
  };

  useEffect(() => {
    return () => {
      stopListening();
    };
  }, [alertId]);

  return (
    <div style={{
      background: 'rgba(15, 23, 42, 0.95)',
      borderRadius: '16px',
      border: '1px solid rgba(255, 255, 255, 0.1)',
      padding: '16px',
      marginTop: '16px',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '12px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          <Radio size={16} color={status === 'LIVE' ? '#ef4444' : 'var(--text-muted)'} className={status === 'LIVE' ? 'animate-pulse' : ''} />
          <span style={{ fontSize: '11px', fontWeight: 900, letterSpacing: '1px', color: 'var(--text-primary)' }}>
            LIVE INTELLIGENCE STREAM
          </span>
          <span style={{
            fontSize: '9px',
            fontWeight: 800,
            padding: '2px 8px',
            borderRadius: '12px',
            background: status === 'LIVE' ? 'rgba(239,68,68,0.2)' : status === 'CONNECTING' ? 'rgba(245,158,11,0.2)' : 'rgba(100,116,139,0.2)',
            color: status === 'LIVE' ? '#ef4444' : status === 'CONNECTING' ? '#f59e0b' : '#94a3b8',
            border: `1px solid ${status === 'LIVE' ? '#ef4444' : status === 'CONNECTING' ? '#f59e0b' : '#64748b'}`
          }}>
            {status === 'LIVE' ? '🔴 BROADCASTING LIVE' : status === 'CONNECTING' ? '⚡ CONNECTING P2P' : status === 'DISCONNECTED' ? 'OFFLINE' : 'STANDBY'}
          </span>
        </div>

        {status === 'IDLE' ? (
          <button
            onClick={startListening}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '6px',
              padding: '6px 12px',
              borderRadius: '8px',
              background: '#ef4444',
              color: 'white',
              border: 'none',
              fontSize: '10px',
              fontWeight: 800,
              cursor: 'pointer',
              letterSpacing: '0.5px'
            }}
          >
            <Video size={14} /> CONNECT LIVE FEED
          </button>
        ) : (
          <button
            onClick={stopListening}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '6px',
              padding: '6px 12px',
              borderRadius: '8px',
              background: 'rgba(255, 255, 255, 0.1)',
              color: '#cbd5e1',
              border: '1px solid rgba(255, 255, 255, 0.2)',
              fontSize: '10px',
              fontWeight: 800,
              cursor: 'pointer'
            }}
          >
            <VideoOff size={14} /> DISCONNECT
          </button>
        )}
      </div>

      <div style={{
        position: 'relative',
        width: '100%',
        height: '240px',
        background: '#000',
        borderRadius: '12px',
        overflow: 'hidden',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        border: '1px solid rgba(255, 255, 255, 0.05)'
      }}>
        <video
          ref={videoRef}
          autoPlay
          playsInline
          controls
          style={{
            width: '100%',
            height: '100%',
            objectFit: 'contain',
            display: status === 'LIVE' ? 'block' : 'none'
          }}
        />

        {status !== 'LIVE' && (
          <div style={{ textAlign: 'center', padding: '24px', color: '#64748b' }}>
            {status === 'CONNECTING' ? (
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '8px' }}>
                <RefreshCw size={24} style={{ animation: 'spin 1s linear infinite', color: '#f59e0b' }} />
                <span style={{ fontSize: '11px', fontWeight: 700, color: '#f59e0b' }}>Awaiting WebRTC P2P stream from field device...</span>
              </div>
            ) : status === 'DISCONNECTED' ? (
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '8px' }}>
                <VideoOff size={24} style={{ color: '#ef4444' }} />
                <span style={{ fontSize: '11px', color: '#94a3b8' }}>Stream ended or field device offline</span>
              </div>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '8px' }}>
                <Video size={28} style={{ color: '#475569' }} />
                <span style={{ fontSize: '11px', color: '#94a3b8' }}>Click "CONNECT LIVE FEED" when field unit broadcasts video</span>
              </div>
            )}
          </div>
        )}
      </div>

      {error && (
        <div style={{ marginTop: '8px', fontSize: '10px', color: '#ef4444', fontWeight: 600 }}>
          ⚠️ {error}
        </div>
      )}
    </div>
  );
}
