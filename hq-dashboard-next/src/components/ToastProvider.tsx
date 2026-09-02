'use client';
import { createContext, useContext, useState, useCallback, useRef, useEffect } from 'react';
import { CheckCircle, AlertTriangle, XCircle, Info, X, Loader2 } from 'lucide-react';

type ToastType = 'success' | 'error' | 'warning' | 'info' | 'loading';

interface Toast {
  id: string;
  type: ToastType;
  title: string;
  message?: string;
  duration?: number; // 0 = permanent until manually dismissed
}

interface ToastContextValue {
  toast: {
    success: (title: string, message?: string) => string;
    error: (title: string, message?: string) => string;
    warning: (title: string, message?: string) => string;
    info: (title: string, message?: string) => string;
    loading: (title: string, message?: string) => string;
    dismiss: (id: string) => void;
    update: (id: string, type: ToastType, title: string, message?: string) => void;
  };
}

const ToastContext = createContext<ToastContextValue | null>(null);

const TOAST_STYLES: Record<ToastType, { border: string; icon: React.ReactNode; glow: string }> = {
  success: {
    border: 'var(--success)',
    glow: '0 0 20px rgba(16,185,129,0.2)',
    icon: <CheckCircle size={16} style={{ color: 'var(--success)', flexShrink: 0 }} />,
  },
  error: {
    border: 'var(--duress)',
    glow: '0 0 20px rgba(239,68,68,0.2)',
    icon: <XCircle size={16} style={{ color: 'var(--duress)', flexShrink: 0 }} />,
  },
  warning: {
    border: 'var(--warning)',
    glow: '0 0 20px rgba(245,158,11,0.2)',
    icon: <AlertTriangle size={16} style={{ color: 'var(--warning)', flexShrink: 0 }} />,
  },
  info: {
    border: 'var(--accent)',
    glow: '0 0 20px rgba(99,102,241,0.2)',
    icon: <Info size={16} style={{ color: 'var(--accent)', flexShrink: 0 }} />,
  },
  loading: {
    border: 'var(--primary)',
    glow: '0 0 20px rgba(59,130,246,0.2)',
    icon: <Loader2 size={16} style={{ color: 'var(--primary)', flexShrink: 0 }} className="spin" />,
  },
};

function ToastItem({ toast, onDismiss }: { toast: Toast; onDismiss: (id: string) => void }) {
  const [visible, setVisible] = useState(false);
  const [leaving, setLeaving] = useState(false);
  const style = TOAST_STYLES[toast.type];

  useEffect(() => {
    // Animate in
    const t = setTimeout(() => setVisible(true), 10);
    return () => clearTimeout(t);
  }, []);

  const handleDismiss = () => {
    setLeaving(true);
    setTimeout(() => onDismiss(toast.id), 300);
  };

  useEffect(() => {
    if (toast.duration === 0) return; // permanent
    const duration = toast.duration ?? (toast.type === 'error' ? 6000 : toast.type === 'loading' ? 0 : 4000);
    if (duration === 0) return;
    const timer = setTimeout(() => handleDismiss(), duration);
    return () => clearTimeout(timer);
  }, [toast.duration, toast.type]);


  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'flex-start',
        gap: 12,
        padding: '14px 16px',
        background: 'var(--bg-secondary)',
        border: `1px solid ${style.border}44`,
        borderLeft: `3px solid ${style.border}`,
        borderRadius: 12,
        boxShadow: `${style.glow}, 0 8px 32px rgba(0,0,0,0.4)`,
        backdropFilter: 'blur(16px)',
        maxWidth: 360,
        minWidth: 280,
        transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
        opacity: visible && !leaving ? 1 : 0,
        transform: visible && !leaving ? 'translateX(0)' : 'translateX(100%)',
        pointerEvents: 'all',
      }}
    >
      {style.icon}
      <div style={{ flex: 1, minWidth: 0 }}>
        <p style={{
          fontSize: 12,
          fontWeight: 900,
          color: 'var(--text-primary)',
          margin: 0,
          letterSpacing: 0.3,
          fontFamily: "'Outfit', sans-serif",
          textTransform: 'uppercase',
        }}>
          {toast.title}
        </p>
        {toast.message && (
          <p style={{
            fontSize: 11,
            color: 'var(--text-muted)',
            margin: '4px 0 0 0',
            lineHeight: 1.4,
            fontFamily: "'Inter', sans-serif",
            fontWeight: 500,
          }}>
            {toast.message}
          </p>
        )}
      </div>
      {toast.type !== 'loading' && (
        <button
          onClick={handleDismiss}
          style={{
            background: 'none',
            border: 'none',
            color: 'var(--text-dim)',
            cursor: 'pointer',
            padding: 2,
            display: 'flex',
            alignItems: 'center',
            flexShrink: 0,
            transition: 'color 0.2s',
          }}
          onMouseEnter={e => (e.currentTarget.style.color = 'var(--text-primary)')}
          onMouseLeave={e => (e.currentTarget.style.color = 'var(--text-dim)')}
        >
          <X size={14} />
        </button>
      )}
    </div>
  );
}

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);
  const counterRef = useRef(0);

  const addToast = useCallback((type: ToastType, title: string, message?: string, duration?: number): string => {
    const id = `toast-${++counterRef.current}`;
    setToasts(prev => [...prev, { id, type, title, message, duration }]);
    return id;
  }, []);

  const dismiss = useCallback((id: string) => {
    setToasts(prev => prev.filter(t => t.id !== id));
  }, []);

  const update = useCallback((id: string, type: ToastType, title: string, message?: string) => {
    setToasts(prev => prev.map(t => t.id === id ? { ...t, type, title, message, duration: type === 'loading' ? 0 : undefined } : t));
  }, []);

  const toast = {
    success: (title: string, message?: string) => addToast('success', title, message),
    error: (title: string, message?: string) => addToast('error', title, message),
    warning: (title: string, message?: string) => addToast('warning', title, message),
    info: (title: string, message?: string) => addToast('info', title, message),
    loading: (title: string, message?: string) => addToast('loading', title, message, 0),
    dismiss,
    update,
  };

  return (
    <ToastContext.Provider value={{ toast }}>
      {children}
      {/* Toast Viewport */}
      <div
        style={{
          position: 'fixed',
          bottom: 24,
          right: 24,
          zIndex: 99999,
          display: 'flex',
          flexDirection: 'column',
          gap: 10,
          alignItems: 'flex-end',
          pointerEvents: 'none',
        }}
      >
        {toasts.map(t => (
          <ToastItem key={t.id} toast={t} onDismiss={dismiss} />
        ))}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast() {
  const ctx = useContext(ToastContext);
  if (!ctx) throw new Error('useToast must be used within a ToastProvider');
  return ctx.toast;
}
