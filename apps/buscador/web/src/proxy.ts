// Antes de mostrar una pantalla: sin sesion -> al inicio de sesion; con sesion -> fuera de las pantallas de acceso.
// (Los datos se protegen aparte, en /backend: este archivo solo ordena la navegacion.)
import { NextRequest, NextResponse } from 'next/server';
import { COOKIE_SESION, segundosRestantes } from '@/lib/sesion-servidor';

const PUBLICAS = ['/auth/login', '/auth/forgot-password', '/auth/reset-password'];

export function proxy(req: NextRequest) {
  const { pathname, search } = req.nextUrl;
  const conSesion = segundosRestantes(req.cookies.get(COOKIE_SESION)?.value) > 0;
  const esPublica = PUBLICAS.some((p) => pathname.startsWith(p));

  if (!conSesion && !esPublica) {
    const destino = new URL('/auth/login', req.url);
    if (pathname !== '/') destino.searchParams.set('volver', pathname + search);
    return NextResponse.redirect(destino);
  }
  if (conSesion && pathname.startsWith('/auth/login')) {
    return NextResponse.redirect(new URL('/inicio', req.url));
  }
  return NextResponse.next();
}

export const config = {
  matcher: ['/((?!backend|sesion|_next|favicon.ico|marca|.*\\.(?:svg|png|jpg|ico|txt)$).*)'],
};
