// Cerrar sesion: borra la cookie del token.
import { NextResponse } from 'next/server';
import { COOKIE_SESION } from '@/lib/sesion-servidor';

export const dynamic = 'force-dynamic';

export function POST() {
  const respuesta = NextResponse.json({ ok: true });
  respuesta.cookies.set(COOKIE_SESION, '', { path: '/', maxAge: 0 });
  return respuesta;
}
