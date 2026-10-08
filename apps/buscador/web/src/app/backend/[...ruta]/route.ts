// Intermediario entre el navegador y la API del Buscador (que corre en la oficina, junto a SQL Server).
// - El navegador llama a /backend/api/... y /backend/system/...; nunca conoce la direccion de la API.
// - Agrega el token (cookie httpOnly) y la IP real de la persona.
// - Aplica la regla de sedes: fuera de las sedes solo trabaja el rol ADMIN GENERAL.
// - Si la API esta detras de Cloudflare Access, se presenta con su token de servicio.
import { NextRequest, NextResponse } from 'next/server';
import {
  COOKIE_SESION,
  MENSAJE_FUERA_DE_SEDE,
  enSede,
  esAdminGeneral,
  ipCliente,
  rolesDelToken,
  segundosRestantes,
} from '@/lib/sesion-servidor';

export const dynamic = 'force-dynamic';

const API_URL = (process.env.BUSCADOR_API_URL ?? '').replace(/\/$/, '');
const RUTAS_PUBLICAS = new Set(['system/auth/login', 'system/auth/forgot-password', 'system/auth/reset-password']);
const CABECERAS_DE_VUELTA = ['content-type', 'content-disposition', 'content-length', 'cache-control'];

type Contexto = { params: Promise<{ ruta: string[] }> };

function json(cuerpo: unknown, estado: number) {
  return NextResponse.json(cuerpo, { status: estado, headers: { 'Cache-Control': 'no-store' } });
}

function sinSesion(respuesta: NextResponse) {
  respuesta.cookies.set(COOKIE_SESION, '', { path: '/', maxAge: 0 });
  return respuesta;
}

async function reenviar(req: NextRequest, { params }: Contexto) {
  const { ruta } = await params;
  const camino = ruta.map(encodeURIComponent).join('/');
  if (!/^(api|system)\//.test(camino)) return json({ message: 'Ruta no encontrada.' }, 404);
  if (!API_URL) return json({ message: 'El Buscador no está conectado a su API (falta BUSCADOR_API_URL).' }, 503);

  const ip = ipCliente(req.headers);
  const token = req.cookies.get(COOKIE_SESION)?.value;
  const publica = RUTAS_PUBLICAS.has(camino);

  if (!publica) {
    if (!token) return sinSesion(json({ message: 'Tu sesión terminó. Vuelve a iniciar sesión.' }, 401));
    if (!esAdminGeneral(rolesDelToken(token)) && !enSede(ip)) {
      return json({ message: MENSAJE_FUERA_DE_SEDE, fueraDeSede: true }, 403);
    }
  }

  const cabeceras = new Headers();
  for (const nombre of ['content-type', 'accept', 'accept-language']) {
    const valor = req.headers.get(nombre);
    if (valor) cabeceras.set(nombre, valor);
  }
  if (token && !publica) cabeceras.set('authorization', `Bearer ${token}`);
  if (ip) cabeceras.set('x-forwarded-for', ip);
  if (process.env.CF_ACCESS_CLIENT_ID && process.env.CF_ACCESS_CLIENT_SECRET) {
    cabeceras.set('cf-access-client-id', process.env.CF_ACCESS_CLIENT_ID);
    cabeceras.set('cf-access-client-secret', process.env.CF_ACCESS_CLIENT_SECRET);
  }

  const conCuerpo = !['GET', 'HEAD'].includes(req.method);
  let respuesta: Response;
  try {
    respuesta = await fetch(`${API_URL}/${camino}${req.nextUrl.search}`, {
      method: req.method,
      headers: cabeceras,
      body: conCuerpo ? req.body : undefined,
      // @ts-expect-error duplex es necesario para reenviar el cuerpo como flujo (archivos de la carga masiva)
      duplex: conCuerpo ? 'half' : undefined,
      redirect: 'manual',
      cache: 'no-store',
      signal: AbortSignal.timeout(300_000),
    });
  } catch {
    return json({ message: 'No se pudo conectar con el Buscador. Intenta de nuevo en unos minutos.' }, 502);
  }

  // Inicio de sesion: el token se guarda en una cookie httpOnly y no se entrega al navegador.
  if (camino === 'system/auth/login') {
    const datos = await respuesta.json().catch(() => null);
    if (!respuesta.ok || !datos || datos.estado !== 1 || !datos.token) {
      return json(datos ?? { message: 'Usuario o contraseña incorrectos.' }, respuesta.ok ? 401 : respuesta.status);
    }
    const roles: string[] = (datos.usuario?.roles ?? []).map((r: { rol: string }) => String(r.rol).toUpperCase());
    if (!esAdminGeneral(roles) && !enSede(ip)) {
      return json({ message: MENSAJE_FUERA_DE_SEDE, fueraDeSede: true }, 403);
    }
    const salida = json({ estado: 1, usuario: datos.usuario }, 200);
    salida.cookies.set(COOKIE_SESION, datos.token, {
      httpOnly: true,
      secure: true,
      sameSite: 'strict',
      path: '/',
      maxAge: segundosRestantes(datos.token) || 900,
    });
    return salida;
  }

  // Comprobar sesion: la API devuelve tambien el token; el navegador no lo necesita.
  if (camino === 'system/auth/check-status' && respuesta.ok) {
    const datos = await respuesta.json().catch(() => null);
    if (datos && typeof datos === 'object') delete datos.token;
    return json(datos, 200);
  }

  const devolver = new Headers({ 'Cache-Control': 'no-store' });
  for (const nombre of CABECERAS_DE_VUELTA) {
    const valor = respuesta.headers.get(nombre);
    if (valor) devolver.set(nombre, valor);
  }
  const salida = new NextResponse(respuesta.body, { status: respuesta.status, headers: devolver });
  return respuesta.status === 401 && !publica ? sinSesion(salida) : salida;
}

export { reenviar as GET, reenviar as POST, reenviar as PUT, reenviar as PATCH, reenviar as DELETE };
