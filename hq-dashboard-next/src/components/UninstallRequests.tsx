'use client';
import { useEffect, useState } from 'react';
import { collection, onSnapshot, query, orderBy } from 'firebase/firestore';
import { db, functions } from '@/lib/firebase';
import { httpsCallable } from 'firebase/functions';
import { ShieldAlert, CheckCircle, Clock, Key, AlertTriangle, ShieldCheck } from 'lucide-react';

interface UninstallRequest {
  uid: string;
  email: string;
  role: string;
  reason: string;
  remarks?: string;
  status: 'PENDING' | 'APPROVED' | 'COMPLETED';
  removalCode?: string;
  approvedBy?: string;
  approvedAt?: any;
  createdAt: any;
  expiresAt?: any;
}

export default function UninstallRequests() {
  const [requests, setRequests] = useState<UninstallRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [processingId, setProcessingId] = useState<string | null>(null);

  useEffect(() => {
    const q = query(collection(db, 'uninstall_requests'), orderBy('createdAt', 'desc'));
    const unsub = onSnapshot(q, (snapshot) => {
      const list = snapshot.docs.map(doc => {
        const data = doc.data();
        return {
          uid: doc.id,
          ...data,
          createdAt: data.createdAt,
          approvedAt: data.approvedAt,
          expiresAt: data.expiresAt,
        } as UninstallRequest;
      });
      setRequests(list);
      setLoading(false);
    }, (err) => {
      console.error('[UNINSTALL_DASHBOARD] Firestore stream failed:', err);
      setLoading(false);
    });

    return () => unsub();
  }, []);

  const handleApprove = async (targetUid: string) => {
    setProcessingId(targetUid);
    try {
      const func = httpsCallable(functions, 'approveAppUninstall');
      await func({ targetUid });
    } catch (e: any) {
      window.alert("Approval failed: " + e.message);
    } finally {
      setProcessingId(null);
    }
  };

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'PENDING':
        return (
          <span style={{ fontSize: 9, fontWeight: 900, background: 'rgba(255,152,0,0.1)', color: '#FF9800', border: '1px solid rgba(255,152,0,0.2)', padding: '4px 8px', borderRadius: 6, fontFamily: "'Inter', sans-serif" }}>
            PENDING COMMAND REVIEW
          </span>
        );
      case 'APPROVED':
        return (
          <span style={{ fontSize: 9, fontWeight: 900, background: 'rgba(76,175,80,0.1)', color: '#4CAF50', border: '1px solid rgba(76,175,80,0.2)', padding: '4px 8px', borderRadius: 6, fontFamily: "'Inter', sans-serif" }}>
            APPROVED & OTP GENERATED
          </span>
        );
      case 'COMPLETED':
        return (
          <span style={{ fontSize: 9, fontWeight: 900, background: 'rgba(255,255,255,0.05)', color: 'var(--text-dim)', border: '1px solid rgba(255,255,255,0.08)', padding: '4px 8px', borderRadius: 6, fontFamily: "'Inter', sans-serif" }}>
            DEACTIVATION COMPLETE
          </span>
        );
      default:
        return null;
    }
  };

  if (loading) {
    return (
      <div style={{ display: 'flex', flex: 1, height: '100%', justifyContent: 'center', alignItems: 'center', minHeight: 300 }}>
        <div style={{ fontSize: 13, color: 'var(--text-muted)', fontWeight: 800, letterSpacing: 1.5 }}>LOADING GOVERNANCE LEDGER...</div>
      </div>
    );
  }

  const pendingCount = requests.filter(r => r.status === 'PENDING').length;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 32 }}>
      {/* Overview stats header */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: 20 }}>
        <div className="tactical-panel glass" style={{ padding: 24, display: 'flex', alignItems: 'center', gap: 20 }}>
          <div style={{ background: pendingCount > 0 ? 'var(--warning-dim)' : 'var(--input-bg)', color: pendingCount > 0 ? 'var(--warning)' : 'var(--text-dim)', padding: 14, borderRadius: 16 }}>
            <ShieldAlert size={24} />
          </div>
          <div>
            <h4 style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 1.5, textTransform: 'uppercase' }}>Awaiting HQ Approval</h4>
            <p style={{ fontSize: 24, fontWeight: 900, color: pendingCount > 0 ? 'var(--warning)' : 'var(--text-primary)', marginTop: 4 }}>{pendingCount}</p>
          </div>
        </div>

        <div className="tactical-panel glass" style={{ padding: 24, display: 'flex', alignItems: 'center', gap: 20 }}>
          <div style={{ background: 'var(--success-dim)', color: 'var(--success)', padding: 14, borderRadius: 16 }}>
            <Key size={24} />
          </div>
          <div>
            <h4 style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 1.5, textTransform: 'uppercase' }}>Active Removal OTPs</h4>
            <p style={{ fontSize: 24, fontWeight: 900, color: 'var(--success)', marginTop: 4 }}>
              {requests.filter(r => r.status === 'APPROVED').length}
            </p>
          </div>
        </div>

        <div className="tactical-panel glass" style={{ padding: 24, display: 'flex', alignItems: 'center', gap: 20 }}>
          <div style={{ background: 'var(--input-bg)', color: 'var(--text-dim)', padding: 14, borderRadius: 16 }}>
            <ShieldCheck size={24} />
          </div>
          <div>
            <h4 style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 1.5, textTransform: 'uppercase' }}>Compliance Deactivations</h4>
            <p style={{ fontSize: 24, fontWeight: 900, color: 'var(--text-primary)', marginTop: 4 }}>
              {requests.filter(r => r.status === 'COMPLETED').length}
            </p>
          </div>
        </div>
      </div>

      {/* Main compliance grid */}
      <div className="tactical-panel glass" style={{ padding: 32 }}>
        <div style={{ marginBottom: 24 }}>
          <h3 style={{ fontSize: 16, fontWeight: 900, color: 'var(--text-primary)', fontFamily: "'Outfit', sans-serif" }}>Active Deactivation Controls</h3>
          <p style={{ fontSize: 12, color: 'var(--text-dim)', marginTop: 4 }}>Approve hardware decommissionings and issue cryptographically-signed OTP codes for device resets.</p>
        </div>

        <div style={{ overflowX: 'auto' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse', textAlign: 'left' }}>
            <thead>
              <tr style={{ borderBottom: '1px solid var(--border)' }}>
                <th style={{ padding: '12px 16px', fontSize: 10, fontWeight: 900, color: 'var(--text-dim)', letterSpacing: 1 }}>OPERATIVE</th>
                <th style={{ padding: '12px 16px', fontSize: 10, fontWeight: 900, color: 'var(--text-dim)', letterSpacing: 1 }}>REASON</th>
                <th style={{ padding: '12px 16px', fontSize: 10, fontWeight: 900, color: 'var(--text-dim)', letterSpacing: 1 }}>JUSTIFICATION</th>
                <th style={{ padding: '12px 16px', fontSize: 10, fontWeight: 900, color: 'var(--text-dim)', letterSpacing: 1 }}>STATUS</th>
                <th style={{ padding: '12px 16px', fontSize: 10, fontWeight: 900, color: 'var(--text-dim)', letterSpacing: 1, textAlign: 'right' }}>DEACTIVATION GATEWAY</th>
              </tr>
            </thead>
            <tbody>
              {requests.map((req) => (
                <tr key={req.uid} style={{ borderBottom: '1px solid var(--border)' }}>
                  {/* Operative profile info */}
                  <td style={{ padding: '20px 16px' }}>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                      <span style={{ fontSize: 13, fontWeight: 800, color: 'var(--text-primary)' }}>{req.email}</span>
                      <span style={{ fontSize: 9, color: 'var(--text-dim)', letterSpacing: 0.5, textTransform: 'uppercase', fontFamily: "'Inter', sans-serif" }}>ROLE: {req.role} · ID: {req.uid.substring(0, 10)}</span>
                    </div>
                  </td>
                  {/* Deactivation Reason */}
                  <td style={{ padding: '20px 16px' }}>
                    <span style={{ fontSize: 12, fontWeight: 700, color: 'var(--text-muted)' }}>{req.reason}</span>
                  </td>
                  {/* Detailed remarks justification */}
                  <td style={{ padding: '20px 16px', maxWidth: 280 }}>
                    <p style={{ fontSize: 11, color: 'var(--text-dim)', lineHeight: 1.5, wordBreak: 'break-word' }}>
                      {req.remarks || 'No remarks supplied'}
                    </p>
                  </td>
                  {/* Current Governance Status */}
                  <td style={{ padding: '20px 16px' }}>
                    {getStatusBadge(req.status)}
                  </td>
                  {/* OTP and command actions */}
                  <td style={{ padding: '20px 16px', textAlign: 'right' }}>
                    {req.status === 'PENDING' && (
                      <button
                        onClick={() => handleApprove(req.uid)}
                        disabled={processingId !== null}
                        className="btn-tactical"
                        style={{
                          background: 'var(--warning-dim)',
                          color: 'var(--warning)',
                          border: '1px solid rgba(245,158,11,0.3)',
                          padding: '8px 16px',
                          display: 'inline-flex',
                          cursor: processingId !== null ? 'not-allowed' : 'pointer'
                        }}
                      >
                        {processingId === req.uid ? 'PROCESSING...' : 'APPROVE DEACTIVATION'}
                      </button>
                    )}
                    {req.status === 'APPROVED' && (
                      <div style={{ display: 'inline-flex', flexDirection: 'column', alignItems: 'flex-end', gap: 4 }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 8, background: 'var(--success-dim)', border: '1px solid rgba(16, 185, 129, 0.2)', padding: '6px 12px', borderRadius: 8 }}>
                          <Key size={12} color="var(--success)" />
                          <span style={{ fontSize: 13, fontWeight: 900, color: 'var(--success)', fontFamily: "'Outfit', sans-serif", letterSpacing: 1.5 }}>
                            {req.removalCode}
                          </span>
                        </div>
                        <span style={{ fontSize: 8, color: 'var(--text-dim)', fontWeight: 600 }}>
                          EXPIRES IN 2 HRS
                        </span>
                      </div>
                    )}
                    {req.status === 'COMPLETED' && (
                      <div style={{ display: 'inline-flex', alignItems: 'center', gap: 6, color: 'var(--text-dim)' }}>
                        <CheckCircle size={14} />
                        <span style={{ fontSize: 10, fontWeight: 800 }}>COMMISSIONED OUT</span>
                      </div>
                    )}
                  </td>
                </tr>
              ))}
              {requests.length === 0 && (
                <tr>
                  <td colSpan={5} style={{ textAlign: 'center', padding: '40px 0', fontSize: 12, color: 'var(--text-dim)' }}>
                    NO HARDWARE DEACTIVATION REQUESTS IN LEDGER
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
