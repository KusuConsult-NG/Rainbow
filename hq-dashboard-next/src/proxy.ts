import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { createServerClient } from '@supabase/ssr';
import { contentSecurityPolicy, newNonce } from '@/lib/csp';

/**
 * The CSP is issued HERE rather than from `next.config.ts` because it carries a
 * per-request nonce, and static header config cannot produce one. Every other
 * security header stays in next.config, where it also covers static assets.
 *
 * Do NOT set a CSP in both places: a response carrying two policies must
 * satisfy BOTH, and the static one has no nonce — so the pair would block the
 * very scripts the nonce exists to allow.
 *
 * The auth guard below is unchanged. Only headers were added around it.
 */
export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;

  const nonce = newNonce();
  const csp = contentSecurityPolicy(
    nonce,
    process.env.NODE_ENV === 'development',
  );

  // Both copies are required. Next reads the nonce back off the REQUEST header
  // while rendering and stamps it onto the scripts it emits; the RESPONSE
  // header is what the browser actually enforces.
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set('x-nonce', nonce);
  requestHeaders.set('Content-Security-Policy', csp);

  const withCsp = (res: NextResponse) => {
    res.headers.set('Content-Security-Policy', csp);
    return res;
  };

  // Allow public routes
  if (
    pathname.startsWith('/login') ||
    pathname.startsWith('/_next') ||
    pathname.startsWith('/api') ||
    pathname.includes('.')
  ) {
    return withCsp(NextResponse.next({ request: { headers: requestHeaders } }));
  }

  // Protect /dashboard and all sub-routes
  if (pathname.startsWith('/dashboard')) {
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
    const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? '';

    // Fail closed: without config we cannot verify anyone, so admit no one.
    if (!supabaseUrl || !supabaseAnonKey) {
      console.error('[PROXY] Supabase env not configured — denying /dashboard access.');
      return withCsp(NextResponse.redirect(new URL('/login', request.url)));
    }

    const response = NextResponse.next({ request: { headers: requestHeaders } });

    const supabase = createServerClient(supabaseUrl, supabaseAnonKey, {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options)
          );
        },
      },
    });

    // Only a real, server-verified Supabase session grants access. The previous
    // `|| hasSessionCookie` fallback trusted an unsigned, client-writable cookie
    // (`document.cookie = '__session=true'`), so anyone could reach the command
    // dashboard by setting one line in devtools.
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (user) {
        return withCsp(response);
      }
    } catch (err) {
      console.error('[PROXY] Session verification failed — failing closed.', err);
    }

    return withCsp(NextResponse.redirect(new URL('/login', request.url)));
  }

  return withCsp(NextResponse.next({ request: { headers: requestHeaders } }));
}

export const config = {
  // Widened from `/dashboard/:path*` so every document response gets a nonced
  // CSP, not just the guarded one. The guard itself still only acts on
  // /dashboard — the branches above are unchanged.
  //
  // Static assets and image optimisation are excluded: they are not documents.
  // `next/link` prefetches are excluded per Next's guidance, since a nonce
  // minted for a response that is never rendered as a document is wasted.
  matcher: [
    {
      source: '/((?!_next/static|_next/image|favicon.ico).*)',
      missing: [
        { type: 'header', key: 'next-router-prefetch' },
        { type: 'header', key: 'purpose', value: 'prefetch' },
      ],
    },
  ],
};
