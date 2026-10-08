// Sesion y regla de sedes. Se usa en el servidor (proxy y rutas /backend), nunca en el navegador.
//
// - El token de la API vive en una cookie httpOnly: el JavaScript del navegador no puede leerlo.
// - Regla de sedes: solo se usa el sistema desde las IPs publicas de las sedes (Lince, Los Olivos).
//   El rol ADMIN GENERAL puede entrar desde cualquier lugar.
//   La IP viene de Cloudflare (cf-connecting-ip): este servidor solo recibe trafico por el tunel.

export const COOKIE_SESION = 'bi_sesion';
export const ROL_TOTAL = 'ADMIN GENERAL';

const CLAIM_ROL_LARGO = 'http://schemas.microsoft.com/ws/2008/06/identity/claims/role';

interface CargaToken {
  exp?: number;
  role?: string | string[];
  [CLAIM_ROL_LARGO]?: string | string[];
}

// Lee la carga del JWT sin verificar la firma. Solo se usa para decidir que mostrar y para la regla de
// sedes: la API verifica la firma en cada peticion, asi que un token falso no obtiene datos.
export function leerToken(token: string | undefined): CargaToken | null {
  if (!token) return null;
  try {
    const parte = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    const bytes = Uint8Array.from(atob(parte), (c) => c.charCodeAt(0));
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return null;
  }
}

export function rolesDelToken(token: string | undefined): string[] {
  const carga = leerToken(token);
  if (!carga) return [];
  const crudo = carga.role ?? carga[CLAIM_ROL_LARGO] ?? [];
  return (Array.isArray(crudo) ? crudo : [crudo]).map((r) => String(r).toUpperCase());
}

export const esAdminGeneral = (roles: string[]) => roles.includes(ROL_TOTAL);

export function segundosRestantes(token: string | undefined): number {
  const exp = leerToken(token)?.exp;
  return exp ? Math.max(0, Math.floor(exp - Date.now() / 1000)) : 0;
}

export function ipCliente(cabeceras: Headers): string {
  return (
    cabeceras.get('cf-connecting-ip') ??
    cabeceras.get('x-forwarded-for')?.split(',')[0]?.trim() ??
    ''
  );
}

// SEDES_IPS: lista separada por comas de IPs o rangos IPv4 (ej. "200.1.2.3/32,190.4.5.0/29").
// Sin configurar = ninguna sede habilitada (solo ADMIN GENERAL puede entrar).
function sedes(): string[] {
  return (process.env.SEDES_IPS ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

function ipANumero(ip: string): number | null {
  const partes = ip.split('.');
  if (partes.length !== 4) return null;
  let n = 0;
  for (const p of partes) {
    const v = Number(p);
    if (!Number.isInteger(v) || v < 0 || v > 255) return null;
    n = n * 256 + v;
  }
  return n;
}

export function enSede(ip: string): boolean {
  const n = ipANumero(ip);
  if (n === null) return false;
  return sedes().some((rango) => {
    const [base, bitsTexto] = rango.split('/');
    const b = ipANumero(base);
    if (b === null) return false;
    const bits = bitsTexto === undefined ? 32 : Number(bitsTexto);
    if (!Number.isInteger(bits) || bits < 0 || bits > 32) return false;
    const tamano = 2 ** (32 - bits);
    return Math.floor(n / tamano) === Math.floor(b / tamano);
  });
}

export const MENSAJE_FUERA_DE_SEDE =
  'El Buscador Interno solo se puede usar desde las sedes de la empresa (Lince y Los Olivos). Si necesitas acceso desde otro lugar, pídeselo a un Administrador General.';
