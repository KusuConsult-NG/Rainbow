'use client';
import { useState, useEffect } from 'react';
import { collection, query, where, onSnapshot } from 'firebase/firestore';
import { db } from '../lib/firebase';
import { AlertTriangle, Info, ShieldAlert, X } from 'lucide-react';

export default function SystemAlertListener() {
  const [activeAlert, setActiveAlert] = useState<any>(null);

  useEffect(() => {
    const q = query(collection(db, 'system_alerts'), where('active', '==', true));
    const unsubscribe = onSnapshot(q, (snap) => {
      if (!snap.empty) {
        setActiveAlert({ id: snap.docs[0].id, ...snap.docs[0].data() });
      } else {
        setActiveAlert(null);
      }
    });
    return () => unsubscribe();
  }, []);

  if (!activeAlert) return null;

  const severity = activeAlert.severity || 'INFO';
  const isCritical = severity === 'CRITICAL';
  
  return (
    <div className="fade-in" style={{
      position: 'fixed', top: 24, left: '50%', transform: 'translateX(-50%)',
      zIndex: 9999, minWidth: 400, maxWidth: '80%',
      background: isCritical ? 'var(--duress)' : 'var(--accent)',
      color: 'white', padding: '16px 24px', borderRadius: 16,
      boxShadow: `0 10px 40px ${isCritical ? 'var(--duress)' : 'var(--accent)'}66`,
      display: 'flex', alignItems: 'center', gap: 20,
      border: '2px solid rgba(255,255,255,0.2)',
      fontFamily: 'Inter, sans-serif'
    }}>
      <div style={{ background: 'rgba(255,255,255,0.2)', padding: 10, borderRadius: 12 }}>
        {isCritical ? <ShieldAlert size={24} /> : <Info size={24} />}
      </div>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 10, fontWeight: 900, letterSpacing: 2, opacity: 0.8, marginBottom: 4 }}>
          SYSTEM ADVISORY: {severity}
        </div>
        <div style={{ fontWeight: 800, fontSize: 14 }}>
          {activeAlert.message?.toUpperCase()}
        </div>
      </div>
      <button 
        onClick={() => setActiveAlert(null)}
        style={{ background: 'transparent', border: 'none', color: 'white', cursor: 'pointer', opacity: 0.5 }}
      >
        <X size={20} />
      </button>
    </div>
  );
}
