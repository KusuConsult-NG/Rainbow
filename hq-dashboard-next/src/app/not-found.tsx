import Link from 'next/link';

/**
 * 404. Deliberately plain and deliberately NOT the crash screen: a mistyped
 * URL is not an incident, and dressing it up in the same red panel would train
 * operators to ignore the one that matters.
 */
export default function NotFound() {
  return (
    <div
      style={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: 24,
        background: '#F5F5F5',
        color: '#1A1A1A',
        fontFamily: 'var(--font-inter), system-ui, -apple-system, sans-serif',
        textAlign: 'center',
      }}
    >
      <div>
        <div style={{ fontSize: 11, fontWeight: 900, letterSpacing: 1.4, color: '#616161' }}>
          404
        </div>
        <h1 style={{ fontSize: 20, fontWeight: 800, margin: '6px 0 8px' }}>
          No such page
        </h1>
        <p style={{ fontSize: 14, color: '#212121', margin: '0 0 20px' }}>
          The operations board is still running — this address just does not exist.
        </p>
        <Link
          href="/dashboard"
          style={{
            display: 'inline-block',
            padding: '11px 20px',
            borderRadius: 10,
            background: 'var(--primary)',
            color: '#ffffff',
            fontSize: 13,
            fontWeight: 800,
            textDecoration: 'none',
          }}
        >
          BACK TO THE BOARD
        </Link>
      </div>
    </div>
  );
}
