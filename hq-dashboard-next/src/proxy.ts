import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { createServerClient } from '@supabase/ssr';

export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Allow public routes
  if (
    pathname.startsWith('/login') ||
    pathname.startsWith('/_next') ||
    pathname.startsWith('/api') ||
    pathname.includes('.')
  ) {
    return NextResponse.next();
  }

  // Protect /dashboard and all sub-routes
  if (pathname.startsWith('/dashboard')) {
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
    const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? '';

    // Fail closed: without config we cannot verify anyone, so admit no one.
    if (!supabaseUrl || !supabaseAnonKey) {
      console.error('[PROXY] Supabase env not configured — denying /dashboard access.');
      return NextResponse.redirect(new URL('/login', request.url));
    }

    const response = NextResponse.next({ request });

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
        return response;
      }
    } catch (err) {
      console.error('[PROXY] Session verification failed — failing closed.', err);
    }

    return NextResponse.redirect(new URL('/login', request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/dashboard/:path*'],
};
