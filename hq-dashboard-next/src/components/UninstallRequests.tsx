'use client';
import { useState } from 'react';
import { ShieldAlert } from 'lucide-react';

export default function UninstallRequests() {
  return (
    <div className="tactical-panel glass" style={{ padding: 24 }}>
      <h2 style={{ fontSize: 18, fontWeight: 900, marginBottom: 16, display: 'flex', alignItems: 'center', gap: 8, color: 'var(--text-primary)' }}>
        <ShieldAlert style={{ width: 20, height: 20, color: 'var(--primary)' }} />
        Staff App Removal Authorization Center
      </h2>
      <p style={{ fontSize: 13, color: 'var(--text-muted)' }}>
        No pending uninstall verification requests from field personnel.
      </p>
    </div>
  );
}
