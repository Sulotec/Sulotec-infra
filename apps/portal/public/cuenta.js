// Cuenta Sulotec: inicio de sesion con OpenID Connect + PKCE contra cuenta.sulotec.com (Keycloak).
// Sin librerias externas. El portal solo usa el nombre y el correo para saludar y adaptar la demo;
// no guarda contrasenas. La sesion se comparte entre pestanas (localStorage) y caduca con la de
// cuenta.sulotec.com (30 minutos sin uso), o antes si la persona cierra sesion.
(() => {
  const meta = (n) => document.querySelector(`meta[name="${n}"]`)?.content;
  const EMISOR = meta('cuenta-emisor');
  const CLIENTE = meta('cuenta-cliente');
  if (!EMISOR || !CLIENTE) return;

  const CALLBACK = `${location.origin}/cuenta/callback`;
  const MIS_PRODUCTOS = '/mis-productos';
  // Rol de Keycloak (grupo "Administradores Generales") que ve todos los productos. Solo cambia lo que
  // se muestra: cada producto privado tiene su propia proteccion (ej. Cloudflare Access en el Buscador).
  const ROL_TOTAL = 'administrador-general';
  const CLAVE_SESION = 'sulotec.sesion';
  // Inicios pendientes por "state": el enlace del correo de verificacion suele abrirse en otra pestana
  const CLAVE_PKCE = 'sulotec.pkce';
  const VIGENCIA_PKCE = 30 * 60 * 1000;

  const leer = (clave) => { try { return JSON.parse(localStorage.getItem(clave)); } catch { return null; } };
  const guardar = (clave, valor) => {
    try { if (valor == null) localStorage.removeItem(clave); else localStorage.setItem(clave, JSON.stringify(valor)); } catch { /* almacenamiento bloqueado */ }
  };

  const b64url = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const aleatorio = (n) => b64url(crypto.getRandomValues(new Uint8Array(n)));
  const sha256 = async (texto) => b64url(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(texto)));
  const leerJwt = (jwt) => {
    const b64 = jwt.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    return JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))));
  };

  const sesion = () => {
    const s = leer(CLAVE_SESION);
    if (s && s.expira > Date.now()) return s;
    if (s) guardar(CLAVE_SESION, null);
    return null;
  };

  // Inicio de sesion en cuenta.sulotec.com. No hay registro libre: las cuentas las crea el equipo de Sulotec.
  // destino: pagina a la que se vuelve (por defecto, la actual)
  async function ir(destino) {
    const verificador = aleatorio(48);
    const estado = aleatorio(16);
    const volver = destino || (location.pathname.startsWith('/cuenta/') ? MIS_PRODUCTOS : location.pathname);
    const pendientes = Object.fromEntries(Object.entries(leer(CLAVE_PKCE) || {}).filter(([, p]) => p.creado > Date.now() - VIGENCIA_PKCE));
    pendientes[estado] = { verificador, volver, creado: Date.now() };
    guardar(CLAVE_PKCE, pendientes);
    const p = new URLSearchParams({
      client_id: CLIENTE,
      response_type: 'code',
      scope: 'openid profile email',
      redirect_uri: CALLBACK,
      state: estado,
      code_challenge: await sha256(verificador),
      code_challenge_method: 'S256',
    });
    location.assign(`${EMISOR}/protocol/openid-connect/auth?${p}`);
  }

  async function completar() {
    const q = new URLSearchParams(location.search);
    const pendientes = leer(CLAVE_PKCE) || {};
    const guardado = pendientes[q.get('state')];
    delete pendientes[q.get('state')];
    guardar(CLAVE_PKCE, Object.keys(pendientes).length ? pendientes : null);
    if (q.get('error')) throw new Error('Cancelaste el inicio de sesión o no se pudo completar. Vuelve a intentarlo.');
    if (!guardado || guardado.creado < Date.now() - VIGENCIA_PKCE || !q.get('code')) throw new Error('El enlace de inicio de sesión no es válido o ya se usó. Vuelve a intentarlo.');
    const r = await fetch(`${EMISOR}/protocol/openid-connect/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'authorization_code', client_id: CLIENTE, code: q.get('code'), redirect_uri: CALLBACK, code_verifier: guardado.verificador }),
    });
    if (!r.ok) throw new Error('No se pudo completar el inicio de sesión. Vuelve a intentarlo en unos minutos.');
    const t = await r.json();
    const datos = leerJwt(t.id_token);
    guardar(CLAVE_SESION, {
      nombre: datos.given_name || datos.name || datos.email,
      correo: datos.email,
      roles: Array.isArray(datos.roles) ? datos.roles : [],
      idToken: t.id_token,
      expira: Date.now() + (t.refresh_expires_in || t.expires_in) * 1000,
    });
    location.replace(guardado.volver && guardado.volver !== '/cuenta/callback' ? guardado.volver : '/');
  }

  function salir() {
    const s = sesion();
    guardar(CLAVE_SESION, null);
    const p = new URLSearchParams({ client_id: CLIENTE, post_logout_redirect_uri: `${location.origin}/` });
    if (s?.idToken) p.set('id_token_hint', s.idToken);
    location.assign(`${EMISOR}/protocol/openid-connect/logout?${p}`);
  }

  const esAdmin = () => Boolean(sesion()?.roles?.includes(ROL_TOTAL));

  window.sulotecCuenta = { sesion, esAdmin, ir, salir };
  // Se marca antes de pintar la pagina para no mostrar botones que no corresponden
  document.documentElement.classList.toggle('con-sesion', Boolean(sesion()));
  document.documentElement.classList.toggle('es-admin', esAdmin());

  document.addEventListener('click', (e) => {
    const boton = e.target.closest('[data-cuenta]');
    if (!boton) return;
    e.preventDefault();
    if (boton.dataset.cuenta === 'salir') salir();
    else ir(boton.dataset.volver);
  });

  document.addEventListener('DOMContentLoaded', () => {
    const s = sesion();
    document.querySelectorAll('[data-cuenta-nombre]').forEach((el) => { el.textContent = s ? s.nombre : ''; });
    // Los correos de consulta ya llevan el nombre y correo de quien tiene sesion
    if (s) document.querySelectorAll('a[data-correo-sesion]').forEach((a) => {
      a.href += `&body=${encodeURIComponent(`Hola, soy ${s.nombre} (${s.correo}). Me gustaría agendar una consulta para solicitar un producto de Sulotec.`)}`;
    });
    if (location.pathname === '/cuenta/entrar') {
      if (s) location.replace(MIS_PRODUCTOS); else ir(MIS_PRODUCTOS);
      return;
    }
    if (location.pathname === MIS_PRODUCTOS && !s) {
      ir(MIS_PRODUCTOS);
      return;
    }
    if (location.pathname === '/cuenta/callback') {
      completar().catch((err) => {
        const el = document.querySelector('[data-cuenta-error]');
        if (el) { el.textContent = err.message; el.hidden = false; }
        document.querySelector('[data-cuenta-cargando]')?.setAttribute('hidden', '');
      });
    }
  });
})();
