// Cliente del navegador: todo pasa por /backend (mismo sitio), que agrega la sesion y la regla de sedes.

export class ErrorApi extends Error {
  constructor(mensaje: string, public estado: number, public fueraDeSede = false) {
    super(mensaje);
  }
}

const MENSAJES: Record<number, string> = {
  400: 'Revisa los datos ingresados.',
  401: 'Tu sesión terminó. Vuelve a iniciar sesión.',
  402: 'No tienes tokens suficientes para esta consulta. Pide más a un Administrador General.',
  403: 'No tienes permiso para esta acción.',
  404: 'No se encontró lo que buscabas.',
  413: 'El archivo es demasiado grande (máximo 5 MB).',
  429: 'Demasiados intentos. Espera un momento y vuelve a intentar.',
};

async function mensajeDe(respuesta: Response): Promise<{ mensaje: string; fueraDeSede: boolean }> {
  const texto = await respuesta.text().catch(() => '');
  try {
    const datos = JSON.parse(texto);
    return {
      mensaje: datos.message || datos.mensaje || datos.title || MENSAJES[respuesta.status] || 'Ocurrió un error.',
      fueraDeSede: Boolean(datos.fueraDeSede),
    };
  } catch {
    return { mensaje: texto.replace(/^"|"$/g, '') || MENSAJES[respuesta.status] || 'Ocurrió un error.', fueraDeSede: false };
  }
}

function alExpirar(estado: number) {
  if (estado === 401 && typeof window !== 'undefined' && !location.pathname.startsWith('/auth/')) {
    location.href = `/auth/login?volver=${encodeURIComponent(location.pathname)}`;
  }
}

export async function pedir<T>(ruta: string, opciones: RequestInit = {}): Promise<T> {
  const cuerpoJson = opciones.body && !(opciones.body instanceof FormData);
  const respuesta = await fetch(`/backend/${ruta.replace(/^\//, '')}`, {
    ...opciones,
    headers: { Accept: 'application/json', ...(cuerpoJson ? { 'Content-Type': 'application/json' } : {}), ...opciones.headers },
    cache: 'no-store',
  });
  if (!respuesta.ok) {
    alExpirar(respuesta.status);
    const { mensaje, fueraDeSede } = await mensajeDe(respuesta);
    throw new ErrorApi(mensaje, respuesta.status, fueraDeSede);
  }
  if (respuesta.status === 204) return undefined as T;
  const texto = await respuesta.text();
  return (texto ? JSON.parse(texto) : null) as T;
}

export const api = {
  get: <T>(ruta: string) => pedir<T>(ruta),
  post: <T>(ruta: string, datos?: unknown) =>
    pedir<T>(ruta, { method: 'POST', body: datos instanceof FormData ? datos : JSON.stringify(datos ?? {}) }),
  put: <T>(ruta: string, datos?: unknown) => pedir<T>(ruta, { method: 'PUT', body: JSON.stringify(datos ?? {}) }),
};

function nombreDeArchivo(disposicion: string | null, porDefecto: string): string {
  if (!disposicion) return porDefecto;
  const utf8 = disposicion.match(/filename\*=UTF-8''([^;]+)/i);
  if (utf8) return decodeURIComponent(utf8[1]);
  const simple = disposicion.match(/filename="?([^";]+)"?/i);
  return simple ? simple[1] : porDefecto;
}

export interface Archivo { blob: Blob; nombre: string }

// Sube un formulario con progreso y recibe un archivo (Excel de la carga masiva).
export function subirYDescargar(ruta: string, datos: FormData, alProgresar: (porcentaje: number) => void, porDefecto: string): Promise<Archivo> {
  return new Promise((resolver, rechazar) => {
    const xhr = new XMLHttpRequest();
    xhr.open('POST', `/backend/${ruta}`);
    xhr.responseType = 'blob';
    xhr.timeout = 300_000;
    xhr.upload.onprogress = (e) => { if (e.lengthComputable) alProgresar(Math.round((e.loaded / e.total) * 100)); };
    xhr.onload = async () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        resolver({ blob: xhr.response, nombre: nombreDeArchivo(xhr.getResponseHeader('Content-Disposition'), porDefecto) });
        return;
      }
      alExpirar(xhr.status);
      const { mensaje, fueraDeSede } = await mensajeDe(new Response(xhr.response, { status: xhr.status }));
      rechazar(new ErrorApi(mensaje, xhr.status, fueraDeSede));
    };
    xhr.onerror = () => rechazar(new ErrorApi('No se pudo conectar con el Buscador.', 0));
    xhr.ontimeout = () => rechazar(new ErrorApi('La carga tardó demasiado. Prueba con menos documentos.', 0));
    xhr.send(datos);
  });
}

export async function descargar(ruta: string, porDefecto: string): Promise<Archivo> {
  const respuesta = await fetch(`/backend/${ruta}`, { cache: 'no-store' });
  if (!respuesta.ok) {
    alExpirar(respuesta.status);
    const { mensaje, fueraDeSede } = await mensajeDe(respuesta);
    throw new ErrorApi(mensaje, respuesta.status, fueraDeSede);
  }
  return { blob: await respuesta.blob(), nombre: nombreDeArchivo(respuesta.headers.get('Content-Disposition'), porDefecto) };
}

export function guardarArchivo({ blob, nombre }: Archivo) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = nombre;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
