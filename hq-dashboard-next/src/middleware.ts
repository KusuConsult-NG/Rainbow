import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

// PRD §4: High-Assurance RBAC — Edge-level route protection
export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;
  
  // Skip public assets and login page
  if (pathname.startsWith('/login') || pathname.startsWith('/_next') || pathname.includes('.')) {
    return NextResponse.next();
  }

  // We check for a session cookie. In a production Firebase environment,
  // we would verify the ID token. For this implementation, we check for presence
  // of the auth cookie. Actual data isolation is enforced at the Firestore layer.
  const session = request.cookies.get('__session');

  if (!session && pathname.startsWith('/dashboard')) {
    return NextResponse.redirect(new URL('/login', request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/dashboard/:path*'],
};
