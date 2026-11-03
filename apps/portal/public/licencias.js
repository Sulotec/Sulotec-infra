// Pagina /licencias (Administrador Universal): licencias de todas las empresas, planes, pedidos de ampliacion,
// reporte de consumo, tokens de los productos y reglas. Todo contra el servicio de licencias con el token de la cuenta.
(() => {
  const API = document.querySelector('meta[name="licencias-api"]')?.content;
  const raiz = document.getElementById('licencias');
  const dialogo = document.getElementById('dialogo');
  if (!API || !raiz || !dialogo) return;
  const form = dialogo.querySelector('form');
  const $ = (sel) => raiz.querySelector(sel);
  const esc = (t) => String(t ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const fecha = (iso) => (iso ? new Date(`${iso}T12:00:00`).toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' }) : '—');
  const fechaHora = (iso) => new Date(iso).toLocaleString('es-PE', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
  const hoy = () => new Date().toISOString().slice(0, 10);
  const periodoActual = () => hoy().slice(0, 7);
  const ESTADOS = { ACTIVA: ['Activa', 'ok'], SOLO_LECTURA: ['Solo lectura', 'alerta'], SUSPENDIDA: ['Suspendida', 'mal'], CANCELADA: ['Cancelada', 'mal'] };
  const REGLAS = { aviso_porcentaje: 'Aviso al % de la bolsa', tolerancia_porcentaje: 'Tolerancia (% sobre la capacidad)', vencimiento_aviso_dias: 'Avisar días antes de vencer', solo_lectura_dias: 'Días en solo lectura', bolsa_extra_vigencia_meses: 'Meses de vigencia de un paquete extra' };
  let productos = []; let planes = []; let licencias = []; let solicitudes = []; let reglas = [];

  const api = async (ruta, { metodo = 'GET', cuerpo, crudo } = {}) => {
    const t = await window.sulotecCuenta?.token?.();
    if (!t) throw Object.assign(new Error('Inicia sesión con tu cuenta Sulotec.'), { codigo: 'SESION_REQUERIDA', estado: 401 });
    let r;
    try {
      r = await fetch(API + ruta, { method: metodo, headers: { Authorization: `Bearer ${t}`, ...(cuerpo ? { 'Content-Type': 'application/json' } : {}) }, body: cuerpo ? JSON.stringify(cuerpo) : undefined });
    } catch {
      throw Object.assign(new Error('El servicio de licencias no responde. Revisa el contenedor «licencias» y la ruta del túnel.'), { codigo: 'SIN_SERVICIO' });
    }
    if (crudo) {
      if (!r.ok) throw new Error(`Error ${r.status} al descargar.`);
      return r;
    }
    const datos = r.headers.get('content-type')?.includes('json') ? await r.json() : null;
    if (!r.ok) throw Object.assign(new Error(datos?.mensaje || `Error ${r.status}`), { codigo: datos?.error, estado: r.status });
    return datos;
  };

  const aviso = (texto, clase = 'mal') => { const m = document.getElementById('mensaje'); m.hidden = !texto; m.className = `mensaje ${clase}`; m.textContent = texto || ''; };
  const planesDe = (producto) => planes.filter((p) => p.producto === producto && p.activo);
  const campo = (etiqueta, html) => `<label>${etiqueta}${html}</label>`;

  // ---------- pintar ----------
  function pintarLicencias() {
    const fp = $('#f-producto')?.value || ''; const fe = $('#f-estado')?.value || '';
    const filas = licencias.filter((l) => (!fp || l.producto === fp) && (!fe || l.estado === fe));
    $('#t-licencias').innerHTML = filas.length ? filas.map((l) => {
      const t = l.tokens;
      const dias = l.dias_para_vencer < 0 ? `hace ${-l.dias_para_vencer} d` : l.dias_para_vencer === 0 ? 'hoy' : `en ${l.dias_para_vencer} d`;
      const inactiva = l.estado === 'SUSPENDIDA' || l.estado === 'CANCELADA';
      return `<tr>
        <td><strong>${esc(l.empresa_nombre)}</strong><br><small class="uuid">${esc(l.empresa_uuid)}</small></td>
        <td>${esc(l.producto_nombre)}<br><small>${esc(l.plan || 'sin plan')}</small></td>
        <td><span class="chip ${ESTADOS[l.estado]?.[1] || ''}">${esc(ESTADOS[l.estado]?.[0] || l.estado)}</span></td>
        <td>${l.usuarios_activos} / ${l.usuarios_max}</td>
        <td>${t ? `${t.usados} / ${t.capacidad} <small>(${t.porcentaje} %${t.tolerancia ? `, ${t.tolerancia} en tolerancia` : ''})</small>` : '—'}</td>
        <td>${esc(fecha(l.vencimiento))}<br><small>${dias}</small></td>
        <td><small>${esc(l.titular?.email || '—')}</small></td>
        <td><select data-accion-de="${l.id}" aria-label="Acción sobre la licencia">
          <option value="">Acción…</option><option value="ampliar">Ampliar</option>${t ? '<option value="bolsa_extra">Paquete extra</option>' : ''}
          <option value="renovar">Renovar</option><option value="cambiar_plan">Cambiar plan</option><option value="titular">Cambiar titular</option>
          ${inactiva ? '<option value="reactivar">Reactivar</option>' : '<option value="suspender">Suspender</option>'}<option value="cancelar">Cancelar</option>
          ${t ? '<option value="consumos">Ver consumos</option>' : ''}<option value="ver">Ver como la empresa</option></select></td>
      </tr>`;
    }).join('') : '<tr><td colspan="8">No hay licencias con ese filtro.</td></tr>';
  }
  function pintarSolicitudes() {
    $('#t-solicitudes').innerHTML = solicitudes.length ? `<table><thead><tr><th>Fecha</th><th>Empresa</th><th>Producto</th><th>Pide</th><th>Comentario</th><th>Quién</th><th></th></tr></thead><tbody>${solicitudes.map((s) => `<tr><td>${esc(fechaHora(s.creado_en))}</td><td>${esc(s.empresa_nombre)}</td><td>${esc(s.producto)}</td><td>${esc(s.que)}${s.cantidad ? ` (+${s.cantidad})` : ''}</td><td>${esc(s.comentario || '—')}</td><td><small>${esc(s.solicitado_por)}</small></td><td><button type="button" class="boton secundario chico" data-atender="${s.id}">Atendida</button></td></tr>`).join('')}</tbody></table>` : '<p class="nota">No hay pedidos pendientes.</p>';
  }
  function pintarPlanes() {
    $('#t-planes').innerHTML = planes.length ? `<table><thead><tr><th>Producto</th><th>Plan</th><th>Usuarios</th><th>Tokens / periodo</th><th>Precio</th><th>Activo</th></tr></thead><tbody>${planes.map((p) => `<tr class="${p.activo ? '' : 'inactivo'}"><td>${esc(productos.find((x) => x.clave === p.producto)?.nombre || p.producto)}</td><td>${esc(p.nombre)}</td><td>${p.usuarios_max}</td><td>${p.tokens_periodo || '—'}</td><td>${p.precio == null ? '—' : `S/ ${p.precio}`}</td><td><button type="button" class="enlace" data-plan-activo="${p.id}" data-valor="${p.activo ? '0' : '1'}">${p.activo ? 'sí · desactivar' : 'no · activar'}</button></td></tr>`).join('')}</tbody></table>` : '<p class="nota">Todavía no hay planes. Crea el primero.</p>';
  }
  function pintarProductos() {
    $('#t-productos').innerHTML = `<table><thead><tr><th>Producto</th><th>Licencia por</th><th>Token</th><th></th></tr></thead><tbody>${productos.map((p) => `<tr><td>${esc(p.nombre)} <small class="uuid">${esc(p.clave)}</small></td><td>${p.usa_tokens ? 'usuarios y tokens' : 'usuarios'}</td><td>${p.tiene_token ? `generado ${p.token_rotado_en ? esc(fechaHora(p.token_rotado_en)) : ''}` : '<span class="chip alerta">sin token</span>'}</td><td><button type="button" class="boton secundario chico" data-token="${esc(p.clave)}">${p.tiene_token ? 'Rotar token' : 'Generar token'}</button></td></tr>`).join('')}</tbody></table>`;
  }
  function pintarReglas() {
    $('#f-reglas').innerHTML = `${reglas.map((r) => campo(esc(REGLAS[r.clave] || r.clave), `<input type="number" min="0" max="1000" name="${esc(r.clave)}" value="${r.valor}" title="${esc(r.descripcion || '')}">`)).join('')}<button type="submit" class="boton boton-azul">Guardar reglas</button>`;
  }
  function pintarReporte(rep) {
    const total = rep.resumen.reduce((s, g) => s + g.tokens, 0);
    $('#t-reporte').innerHTML = rep.resumen.length ? `<table><thead><tr><th>Empresa</th><th>Producto</th><th>Periodo</th><th>Consultas</th><th>Tokens</th><th>De la bolsa</th><th>De extra</th><th>Tolerancia (facturar)</th><th>Hecho por Sulotec</th></tr></thead><tbody>${rep.resumen.map((g) => `<tr><td>${esc(g.empresa_nombre)}</td><td>${esc(g.producto_nombre)}</td><td>${esc(g.periodo)}</td><td>${g.consultas}</td><td>${g.tokens}</td><td>${g.de_bolsa}</td><td>${g.de_extra}</td><td>${g.tolerancia}</td><td>${g.hecho_por_sulotec}</td></tr>`).join('')}</tbody></table><p class="nota">${rep.resumen.length} líneas · ${total} tokens en total.</p>` : '<p class="nota">Sin consumos en ese rango.</p>';
  }

  async function cargarTodo() {
    aviso('');
    try {
      [productos, planes, licencias, solicitudes, reglas] = await Promise.all([api('/v1/admin/productos'), api('/v1/admin/planes'), api('/v1/admin/licencias'), api('/v1/admin/solicitudes?pendientes=1'), api('/v1/admin/reglas')]);
      $('#f-producto').innerHTML = `<option value="">Todos los productos</option>${productos.map((p) => `<option value="${esc(p.clave)}">${esc(p.nombre)}</option>`).join('')}`;
      pintarLicencias(); pintarSolicitudes(); pintarPlanes(); pintarProductos(); pintarReglas();
      raiz.hidden = false;
    } catch (e) {
      raiz.hidden = true;
      if (e.estado === 401) { aviso('Inicia sesión con tu cuenta Sulotec para administrar las licencias.'); document.getElementById('entrar').hidden = false; }
      else aviso(e.message);
    }
  }

  // ---------- dialogo generico ----------
  let alEnviar = null;
  function abrir(titulo, camposHtml, enviar, textoBoton = 'Guardar') {
    form.innerHTML = `<h3>${titulo}</h3>${camposHtml}<p class="error" hidden></p><div class="acciones"><button type="submit" class="boton boton-azul">${textoBoton}</button><button type="button" class="boton secundario" data-cerrar>Cancelar</button></div>`;
    alEnviar = enviar;
    dialogo.showModal();
  }
  function mostrar(titulo, html) {
    form.innerHTML = `<h3>${titulo}</h3>${html}<div class="acciones"><button type="button" class="boton boton-azul" data-cerrar>Cerrar</button></div>`;
    alEnviar = null;
    dialogo.showModal();
  }
  form.addEventListener('click', (e) => { if (e.target.closest('[data-cerrar]')) dialogo.close(); });
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (!alEnviar) return dialogo.close();
    const boton = form.querySelector('button[type=submit]'); const error = form.querySelector('.error');
    boton.disabled = true; error.hidden = true;
    try {
      await alEnviar(Object.fromEntries(new FormData(form)));
      dialogo.close();
      await cargarTodo();
    } catch (err) { error.textContent = err.message; error.hidden = false; }
    finally { boton.disabled = false; }
  });
  const num = (v) => (v === '' || v == null ? undefined : Number(v));
  const limpio = (o) => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined && v !== ''));

  function accion(l, que) {
    const t = l.tokens;
    const base = { id: l.id };
    switch (que) {
      case 'ampliar': return abrir(`Ampliar · ${esc(l.empresa_nombre)} · ${esc(l.producto_nombre)}`,
        campo('Usuarios máximos', `<input type="number" name="usuarios_max" min="0" value="${l.usuarios_max}">`) + (t ? campo('Tokens por periodo', `<input type="number" name="tokens_periodo" min="0" value="${t.bolsa}">`) : ''),
        (d) => api(`/v1/admin/licencias/${base.id}`, { metodo: 'PATCH', cuerpo: limpio({ accion: 'ampliar', usuarios_max: num(d.usuarios_max), tokens_periodo: num(d.tokens_periodo) }) }));
      case 'bolsa_extra': return abrir(`Paquete extra · ${esc(l.empresa_nombre)}`,
        campo('Cantidad de tokens', '<input type="number" name="cantidad" min="1" required>') + campo('Vence (opcional, por defecto 12 meses)', '<input type="date" name="vence">'),
        (d) => api(`/v1/admin/licencias/${base.id}/bolsas-extra`, { metodo: 'POST', cuerpo: limpio({ cantidad: num(d.cantidad), vence: d.vence }) }));
      case 'renovar': return abrir(`Renovar · ${esc(l.empresa_nombre)} · ${esc(l.producto_nombre)}`,
        campo('Nuevo vencimiento', `<input type="date" name="vencimiento" min="${hoy()}" required>`),
        (d) => api(`/v1/admin/licencias/${base.id}`, { metodo: 'PATCH', cuerpo: { accion: 'renovar', vencimiento: d.vencimiento } }));
      case 'cambiar_plan': { const ps = planesDe(l.producto); if (!ps.length) return mostrar('Sin planes', `<p>No hay planes activos para ${esc(l.producto_nombre)}. Crea uno primero.</p>`);
        return abrir(`Cambiar plan · ${esc(l.empresa_nombre)}`, campo('Plan', `<select name="plan_id">${ps.map((p) => `<option value="${p.id}" ${p.id === l.plan_id ? 'selected' : ''}>${esc(p.nombre)} · ${p.usuarios_max} usuarios${p.tokens_periodo ? ` · ${p.tokens_periodo} tokens` : ''}</option>`).join('')}</select>`),
          (d) => api(`/v1/admin/licencias/${base.id}`, { metodo: 'PATCH', cuerpo: { accion: 'cambiar_plan', plan_id: num(d.plan_id) } })); }
      case 'titular': return abrir(`Titular · ${esc(l.empresa_nombre)} · ${esc(l.producto_nombre)}`,
        campo('Correo del Administrador General', `<input type="email" name="email" value="${esc(l.titular?.email || '')}" required>`) + campo('Nombre', `<input type="text" name="nombre" value="${esc(l.titular?.nombre || '')}">`),
        (d) => api(`/v1/admin/licencias/${base.id}`, { metodo: 'PATCH', cuerpo: limpio({ accion: 'titular', email: d.email, nombre: d.nombre }) }));
      case 'suspender': return abrir(`Suspender · ${esc(l.empresa_nombre)} · ${esc(l.producto_nombre)}`, '<p>El producto quedará suspendido para esa empresa (los datos se conservan). ¿Seguro?</p>',
        () => api(`/v1/admin/licencias/${base.id}`, { metodo: 'PATCH', cuerpo: { accion: 'suspender' } }), 'Suspender');
      case 'cancelar': return abrir(`Cancelar · ${esc(l.empresa_nombre)} · ${esc(l.producto_nombre)}`, '<p>La licencia queda cancelada (fin del contrato). ¿Seguro?</p>',
        () => api(`/v1/admin/licencias/${base.id}`, { metodo: 'PATCH', cuerpo: { accion: 'cancelar' } }), 'Cancelar la licencia');
      case 'reactivar': return abrir(`Reactivar · ${esc(l.empresa_nombre)} · ${esc(l.producto_nombre)}`,
        campo(`Vencimiento (obligatorio si ya venció; actual ${esc(l.vencimiento)})`, `<input type="date" name="vencimiento" min="${hoy()}">`),
        (d) => api(`/v1/admin/licencias/${base.id}`, { metodo: 'PATCH', cuerpo: limpio({ accion: 'reactivar', vencimiento: d.vencimiento }) }));
      case 'consumos': return verConsumos(l);
      case 'ver': window.open(`/mi-licencia?empresa=${encodeURIComponent(l.empresa_uuid)}`, '_blank'); return undefined;
      default: return undefined;
    }
  }
  async function verConsumos(l, periodo = periodoActual()) {
    const filas = await api(`/v1/admin/licencias/${l.id}/consumos?periodo=${periodo}`);
    mostrar(`Consumos · ${esc(l.empresa_nombre)} · ${esc(l.producto_nombre)} · ${periodo}`, `<div class="tabla">${filas.length ? `<table><thead><tr><th>Fecha</th><th>Usuario</th><th>Tipo</th><th>Cant.</th><th>Nivel</th></tr></thead><tbody>${filas.map((f) => `<tr class="${f.anulado_en ? 'inactivo' : ''}"><td>${esc(fechaHora(f.creado_en))}</td><td>${esc(f.usuario || '—')}</td><td>${esc(f.tipo)}</td><td>${f.cantidad}</td><td>${f.anulado_en ? 'anulado' : esc(f.nivel)}${f.hecho_por_sulotec ? ' · Sulotec' : ''}</td></tr>`).join('')}</tbody></table>` : '<p class="nota">Sin consumos en este periodo.</p>'}</div>`);
  }

  // Identificador corto a partir del nombre: "Caja Piura S.A." -> caja-piura-s-a
  const slugDe = (nombre) => nombre.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 39);

  async function nuevaLicencia() {
    // Las empresas viven en Keycloak: se elige una o se crea desde aqui (el servicio la crea con su UUID).
    let empresas = null;
    try { empresas = await api('/v1/admin/empresas'); } catch (e) { aviso(`No se pudo leer la lista de empresas de Keycloak (${e.message}). Puedes escribir el UUID a mano.`); }
    const campoEmpresa = empresas
      ? campo('Empresa', `<select name="empresa_sel" id="d-empresa" required><option value="">Elige una empresa…</option>${empresas.map((e) => `<option value="${esc(e.uuid)}" data-nombre="${esc(e.nombre)}">${esc(e.nombre)} (${esc(e.slug)})${e.productos.length ? ` · tiene: ${esc(e.productos.join(', '))}` : ''}</option>`).join('')}<option value="__nueva__">+ Empresa nueva (se crea en la cuenta Sulotec)</option></select>`)
        + `<div id="d-nueva" class="nueva-empresa" hidden>${campo('Nombre de la empresa nueva', '<input type="text" name="nueva_nombre" maxlength="120">')}${campo('Identificador corto (minúsculas y guiones; es el nombre del grupo en Keycloak)', '<input type="text" name="nueva_slug" pattern="[a-z0-9][a-z0-9-]{1,38}" placeholder="caja-piura">')}</div>`
      : campo('UUID de la empresa (el de Keycloak, grupo Empresas)', '<input type="text" name="empresa_uuid" pattern="[0-9a-fA-F-]{36}" required placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx">')
        + campo('Nombre de la empresa', '<input type="text" name="empresa_nombre" required>');
    abrir('Nueva licencia',
      campoEmpresa
      + campo('Producto', `<select name="producto" id="d-producto">${productos.map((p) => `<option value="${esc(p.clave)}">${esc(p.nombre)}</option>`).join('')}</select>`)
      + campo('Plan (opcional; si eliges uno, toma sus cupos)', '<select name="plan_id" id="d-plan"><option value="">Sin plan</option></select>')
      + campo('Usuarios máximos', '<input type="number" name="usuarios_max" min="0">')
      + campo('Tokens por periodo (solo productos con tokens)', '<input type="number" name="tokens_periodo" min="0">')
      + campo('Inicio', `<input type="date" name="inicio" value="${hoy()}">`) + campo('Vencimiento (por defecto, un mes)', '<input type="date" name="vencimiento">')
      + campo('Correo del Administrador General (titular)', '<input type="email" name="titular_email">') + campo('Nombre del titular', '<input type="text" name="titular_nombre">'),
      async (d) => {
        let uuid = d.empresa_uuid?.trim().toLowerCase(); let nombre = d.empresa_nombre;
        if (empresas) {
          if (d.empresa_sel === '__nueva__') {
            const creada = await api('/v1/admin/empresas', { metodo: 'POST', cuerpo: { nombre: d.nueva_nombre?.trim(), slug: d.nueva_slug?.trim(), productos: [] } });
            uuid = creada.uuid; nombre = creada.nombre;
          } else {
            uuid = d.empresa_sel; nombre = empresas.find((e) => e.uuid === uuid)?.nombre;
          }
        }
        return api('/v1/admin/licencias', { metodo: 'POST', cuerpo: limpio({ empresa_uuid: uuid, empresa_nombre: nombre, producto: d.producto, plan_id: num(d.plan_id), usuarios_max: num(d.usuarios_max), tokens_periodo: num(d.tokens_periodo), inicio: d.inicio, vencimiento: d.vencimiento, titular_email: d.titular_email, titular_nombre: d.titular_nombre }) });
      },
      'Crear licencia');
    const se = form.querySelector('#d-empresa'); const dn = form.querySelector('#d-nueva');
    if (se) {
      se.addEventListener('change', () => { dn.hidden = se.value !== '__nueva__'; dn.querySelectorAll('input').forEach((i) => { i.required = !dn.hidden; }); });
      const nn = form.querySelector('[name=nueva_nombre]'); const ns = form.querySelector('[name=nueva_slug]');
      nn.addEventListener('input', () => { if (!ns.dataset.manual) ns.value = slugDe(nn.value); });
      ns.addEventListener('input', () => { ns.dataset.manual = '1'; });
    }
    const sp = form.querySelector('#d-producto'); const spl = form.querySelector('#d-plan');
    const llenar = () => { spl.innerHTML = `<option value="">Sin plan</option>${planesDe(sp.value).map((p) => `<option value="${p.id}">${esc(p.nombre)} · ${p.usuarios_max} usuarios${p.tokens_periodo ? ` · ${p.tokens_periodo} tokens` : ''}</option>`).join('')}`; };
    sp.addEventListener('change', llenar); llenar();
  }
  function nuevoPlan() {
    abrir('Nuevo plan',
      campo('Producto', `<select name="producto">${productos.map((p) => `<option value="${esc(p.clave)}">${esc(p.nombre)}</option>`).join('')}</select>`)
      + campo('Nombre', '<input type="text" name="nombre" required placeholder="Básico, Pro…">') + campo('Usuarios máximos', '<input type="number" name="usuarios_max" min="0" required>')
      + campo('Tokens por periodo (0 si no usa tokens)', '<input type="number" name="tokens_periodo" min="0" value="0">') + campo('Precio mensual (S/, opcional)', '<input type="number" name="precio" min="0" step="0.01">'),
      (d) => api('/v1/admin/planes', { metodo: 'POST', cuerpo: limpio({ producto: d.producto, nombre: d.nombre, usuarios_max: num(d.usuarios_max), tokens_periodo: num(d.tokens_periodo), precio: num(d.precio) }) }), 'Crear plan');
  }

  // ---------- eventos ----------
  raiz.addEventListener('change', async (e) => {
    const sel = e.target.closest('select[data-accion-de]');
    if (sel) { const l = licencias.find((x) => String(x.id) === sel.dataset.accionDe); const que = sel.value; sel.value = ''; if (l && que) { try { await accion(l, que); } catch (err) { aviso(err.message); } } return; }
    if (e.target.id === 'f-producto' || e.target.id === 'f-estado') pintarLicencias();
  });
  raiz.addEventListener('click', async (e) => {
    const b = e.target.closest('button');
    if (!b) return;
    try {
      if (b.id === 'b-nueva') await nuevaLicencia();
      else if (b.id === 'b-plan') nuevoPlan();
      else if (b.id === 'b-excel') {
        const d = new FormData($('#f-reporte'));
        const r = await api(`/v1/admin/consumos?periodo_desde=${d.get('desde')}&periodo_hasta=${d.get('hasta')}&formato=xlsx`, { crudo: true });
        const url = URL.createObjectURL(await r.blob()); const a = document.createElement('a'); a.href = url; a.download = `consumo-${d.get('desde')}-${d.get('hasta')}.xlsx`; a.click(); URL.revokeObjectURL(url);
      } else if (b.dataset.atender) { await api(`/v1/admin/solicitudes/${b.dataset.atender}`, { metodo: 'PATCH' }); solicitudes = await api('/v1/admin/solicitudes?pendientes=1'); pintarSolicitudes(); }
      else if (b.dataset.planActivo) { await api(`/v1/admin/planes/${b.dataset.planActivo}`, { metodo: 'PATCH', cuerpo: { activo: b.dataset.valor === '1' } }); planes = await api('/v1/admin/planes'); pintarPlanes(); }
      else if (b.dataset.token) {
        abrir(`${productos.find((p) => p.clave === b.dataset.token)?.tiene_token ? 'Rotar' : 'Generar'} el token de ${esc(b.dataset.token)}`, '<p>El token anterior deja de valer en cuanto se genera el nuevo. Pégalo en el .env del producto como LICENCIAS_TOKEN y reinícialo.</p>',
          async () => { const r = await api(`/v1/admin/productos/${b.dataset.token}/token`, { metodo: 'POST' }); setTimeout(() => mostrar(`Token de ${esc(r.producto)} (se muestra una sola vez)`, `<p class="token">${esc(r.token)}</p><p class="nota">${esc(r.aviso)}</p>`), 50); }, 'Generar');
      }
    } catch (err) { aviso(err.message); }
  });
  raiz.addEventListener('submit', async (e) => {
    e.preventDefault();
    try {
      if (e.target.id === 'f-reporte') { const d = new FormData(e.target); pintarReporte(await api(`/v1/admin/consumos?periodo_desde=${d.get('desde')}&periodo_hasta=${d.get('hasta')}`)); }
      else if (e.target.id === 'f-reglas') { const d = Object.fromEntries(new FormData(e.target)); const cuerpo = Object.fromEntries(Object.entries(d).map(([k, v]) => [k, Number(v)])); reglas = await api('/v1/admin/reglas', { metodo: 'PATCH', cuerpo }); pintarReglas(); aviso('Reglas guardadas.', 'ok'); }
    } catch (err) { aviso(err.message); }
  });

  raiz.querySelectorAll('#f-reporte input[type=month]').forEach((i) => { i.value = periodoActual(); });
  if (!window.sulotecCuenta?.sesion()) { aviso('Inicia sesión con tu cuenta Sulotec para administrar las licencias.'); document.getElementById('entrar').hidden = false; return; }
  if (!window.sulotecCuenta.esAdmin()) { aviso('Esta página es solo para el Administrador Universal de Sulotec. Si eres el administrador de una empresa, entra a Mi licencia.'); return; }
  cargarTodo();
})();
