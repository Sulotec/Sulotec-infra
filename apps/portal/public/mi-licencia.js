// Pagina /mi-licencia: el Administrador General (titular) ve las licencias de su empresa, su consumo y pide ampliaciones.
// Llama al servicio de licencias con el token de la cuenta Sulotec (window.sulotecCuenta.token()).
(() => {
  const API = document.querySelector('meta[name="licencias-api"]')?.content;
  const cont = document.getElementById('mi-licencia');
  if (!API || !cont) return;
  const params = new URLSearchParams(location.search);
  const empresaForzada = params.get('empresa');
  const conEmpresa = (ruta) => (empresaForzada ? `${ruta}${ruta.includes('?') ? '&' : '?'}empresa=${encodeURIComponent(empresaForzada)}` : ruta);

  const api = async (ruta, { metodo = 'GET', cuerpo } = {}) => {
    const t = await window.sulotecCuenta?.token?.();
    if (!t) throw Object.assign(new Error('Inicia sesión para ver tu licencia.'), { codigo: 'SESION_REQUERIDA' });
    let r;
    try {
      r = await fetch(API + ruta, { method: metodo, headers: { Authorization: `Bearer ${t}`, ...(cuerpo ? { 'Content-Type': 'application/json' } : {}) }, body: cuerpo ? JSON.stringify(cuerpo) : undefined });
    } catch {
      throw Object.assign(new Error('El servicio de licencias no responde. Inténtalo en unos minutos.'), { codigo: 'SIN_SERVICIO' });
    }
    const datos = r.headers.get('content-type')?.includes('json') ? await r.json() : null;
    if (!r.ok) throw Object.assign(new Error(datos?.mensaje || `Error ${r.status}`), { codigo: datos?.error, estado: r.status });
    return datos;
  };
  const esc = (t) => String(t ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const fecha = (iso) => (iso ? new Date(`${iso}T12:00:00`).toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' }) : '—');
  const fechaHora = (iso) => new Date(iso).toLocaleString('es-PE', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
  const periodoActual = () => new Date().toISOString().slice(0, 7);
  const ESTADOS = { ACTIVA: ['Activa', 'ok'], SOLO_LECTURA: ['Vencida: solo lectura', 'alerta'], SUSPENDIDA: ['Suspendida', 'mal'], CANCELADA: ['Cancelada', 'mal'] };
  const NIVELES = { normal: ['Bolsa disponible', 'ok'], aviso: ['Ya usaste más del 80 % de la bolsa', 'alerta'], tolerancia: ['Bolsa agotada: estás en la tolerancia, que se factura aparte', 'alerta'], bloqueado: ['Bolsa y tolerancia agotadas: las consultas están bloqueadas', 'mal'] };
  const barra = (usados, total, clase) => `<div class="barra ${clase || ''}"><span style="width:${total ? Math.min(100, Math.round((usados / total) * 100)) : 0}%"></span></div>`;

  function tarjeta(l) {
    const [estadoTexto, estadoClase] = ESTADOS[l.estado] || [l.estado, ''];
    const vence = l.dias_para_vencer < 0 ? `Venció el ${fecha(l.vencimiento)}` : l.dias_para_vencer === 0 ? 'Vence hoy' : `Vence el ${fecha(l.vencimiento)} (en ${l.dias_para_vencer} días)`;
    const t = l.tokens;
    const nivel = t ? NIVELES[t.nivel] || [t.nivel, ''] : null;
    const tokens = t
      ? `<div class="medida"><div class="fila"><strong>Tokens del periodo ${esc(l.periodo)}</strong><span>${t.usados} de ${t.capacidad}</span></div>${barra(t.usados, t.capacidad, nivel[1])}
         <p class="nota ${nivel[1]}">${esc(nivel[0])}${t.extra ? ` · incluye ${t.extra} de paquetes extra` : ''}${t.tolerancia ? ` · ${t.tolerancia} consumidos en tolerancia` : ''}</p></div>`
      : '<p class="nota">Este producto se licencia solo por usuarios.</p>';
    return `<article class="licencia" data-producto="${esc(l.producto)}">
      <div class="cabecera"><h3>${esc(l.producto_nombre)}</h3><span class="chip ${estadoClase}">${esc(estadoTexto)}</span></div>
      <p class="plan">${l.plan ? `Plan ${esc(l.plan)} · ` : ''}${esc(vence)}</p>
      <div class="medida"><div class="fila"><strong>Usuarios activos</strong><span>${l.usuarios_activos} de ${l.usuarios_max}</span></div>${barra(l.usuarios_activos, l.usuarios_max, l.puede_crear_usuarios ? 'ok' : 'alerta')}
        <p class="nota">${l.puede_crear_usuarios ? 'Puedes crear más sub-usuarios en el producto.' : l.estado === 'ACTIVA' ? 'Llegaste al máximo de usuarios de tu plan.' : 'La licencia no está activa.'}</p></div>
      ${tokens}
      <div class="acciones">
        ${t ? `<button type="button" class="boton secundario" data-consumo="${esc(l.producto)}">Ver consumo</button>` : ''}
        <button type="button" class="boton boton-azul" data-ampliar="${esc(l.producto)}">Pedir ampliación</button>
      </div>
      <div class="detalle" hidden></div>
    </article>`;
  }

  function mostrarError(e) {
    if (e.codigo === 'SESION_REQUERIDA' || e.estado === 401) {
      cont.innerHTML = '<div class="vacio"><p>Inicia sesión con tu cuenta Sulotec para ver la licencia de tu empresa.</p><button type="button" class="boton boton-azul" data-cuenta="ingresar" data-volver="/mi-licencia">Iniciar sesión</button></div>';
    } else {
      cont.innerHTML = `<p class="vacio">${esc(e.message)}</p>`;
    }
  }

  async function cargar() {
    cont.innerHTML = '<p class="vacio">Cargando tu licencia…</p>';
    try {
      const lista = await api(conEmpresa('/v1/mi-licencia'));
      if (!lista.length) {
        cont.innerHTML = '<p class="vacio">Tu empresa todavía no tiene licencias registradas. Si crees que es un error, escríbenos a contacto@sulotec.com.</p>';
        return;
      }
      cont.innerHTML = lista.map(tarjeta).join('');
    } catch (e) { mostrarError(e); }
  }

  async function verConsumo(producto, caja, periodo = periodoActual()) {
    caja.hidden = false;
    caja.innerHTML = '<p class="nota">Cargando el consumo…</p>';
    try {
      const filas = await api(conEmpresa(`/v1/mi-licencia/${encodeURIComponent(producto)}/consumos?periodo=${periodo}`));
      const cuerpo = filas.length
        ? filas.map((f) => `<tr class="${f.anulado_en ? 'anulado' : ''}"><td>${esc(fechaHora(f.creado_en))}</td><td>${esc(f.usuario || '—')}</td><td>${esc(f.tipo)}</td><td>${f.cantidad}</td><td>${f.anulado_en ? 'anulado' : esc(f.nivel)}${f.hecho_por_sulotec ? ' · Sulotec' : ''}</td></tr>`).join('')
        : '<tr><td colspan="5">Sin consumos en ese periodo.</td></tr>';
      caja.innerHTML = `<div class="fila"><label>Periodo <input type="month" value="${periodo}" data-periodo="${esc(producto)}"></label><span>${filas.length} consultas</span></div>
        <div class="tabla"><table><thead><tr><th>Fecha</th><th>Usuario</th><th>Tipo</th><th>Cant.</th><th>Nivel</th></tr></thead><tbody>${cuerpo}</tbody></table></div>`;
    } catch (e) { caja.innerHTML = `<p class="nota mal">${esc(e.message)}</p>`; }
  }

  function formularioAmpliar(producto, caja) {
    caja.hidden = false;
    caja.innerHTML = `<form data-form-ampliar="${esc(producto)}" class="form">
      <label>Qué necesitas <select name="que" required><option value="usuarios">Más usuarios</option><option value="tokens">Más tokens</option><option value="plan">Un plan mayor</option></select></label>
      <label>Cantidad (opcional) <input name="cantidad" type="number" min="1" step="1" placeholder="por ejemplo 5"></label>
      <label>Comentario (opcional) <textarea name="comentario" maxlength="500" rows="2" placeholder="Cuéntanos qué cambió"></textarea></label>
      <div class="acciones"><button type="submit" class="boton boton-azul">Enviar el pedido</button><button type="button" class="boton secundario" data-cerrar>Cancelar</button></div>
      <p class="nota">Sulotec recibe el pedido por correo y te responde con la cotización. Nada cambia hasta que lo confirmes.</p>
    </form>`;
  }

  cont.addEventListener('click', (e) => {
    const b = e.target.closest('button');
    if (!b) return;
    const tarjetaEl = b.closest('.licencia');
    const caja = tarjetaEl?.querySelector('.detalle');
    if (b.dataset.consumo) verConsumo(b.dataset.consumo, caja);
    else if (b.dataset.ampliar) formularioAmpliar(b.dataset.ampliar, caja);
    else if (b.hasAttribute('data-cerrar')) { caja.hidden = true; caja.innerHTML = ''; }
  });
  cont.addEventListener('change', (e) => {
    const sel = e.target.closest('input[data-periodo]');
    if (sel && /^\d{4}-\d{2}$/.test(sel.value)) verConsumo(sel.dataset.periodo, sel.closest('.detalle'), sel.value);
  });
  cont.addEventListener('submit', async (e) => {
    const form = e.target.closest('form[data-form-ampliar]');
    if (!form) return;
    e.preventDefault();
    const d = new FormData(form);
    const cuerpo = { que: d.get('que'), comentario: d.get('comentario') || undefined };
    if (d.get('cantidad')) cuerpo.cantidad = Number(d.get('cantidad'));
    const boton = form.querySelector('button[type=submit]');
    boton.disabled = true;
    try {
      await api(conEmpresa(`/v1/mi-licencia/${encodeURIComponent(form.dataset.formAmpliar)}/ampliar`), { metodo: 'POST', cuerpo });
      form.closest('.detalle').innerHTML = '<p class="nota ok">Listo: Sulotec recibió tu pedido y te escribirá con la cotización.</p>';
    } catch (err) {
      boton.disabled = false;
      form.insertAdjacentHTML('beforeend', `<p class="nota mal">${esc(err.message)}</p>`);
    }
  });

  cargar();
})();
