// Comportamiento de las demos publicas (/demo/...). Sin datos reales ni llamadas a servidores.
// - Visitante sin cuenta: recorre las demos libremente unos minutos (sumados entre todas las demos);
//   despues una ventana que no se puede cerrar le pide iniciar sesion para seguir.
// - Con cuenta (public/cuenta.js): recorre la demo sin limite y se le recomienda agendar una consulta.
document.addEventListener('DOMContentLoaded', () => {
  const app = document.querySelector('.app');
  const invitacion = document.getElementById('invitacion');
  const consulta = document.getElementById('consulta');
  const aviso = document.querySelector('.aviso-bloqueo');
  const reducido = matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (!app || !invitacion) return;

  const sesion = window.sulotecCuenta?.sesion?.() || null;
  const limiteAcciones = Number(app.dataset.acciones) || 3;
  const limiteSegundos = Number(app.dataset.segundos) || 120;
  const segundosConsulta = Number(app.dataset.consulta) || 60;
  const conLimite = app.dataset.limite === 'si'; // solo si las cuentas estan activas (si no, nadie podria seguir)
  let accionesBloqueadas = 0;

  const abrir = (dialogo) => { if (dialogo && !dialogo.open) dialogo.showModal(); };
  const abrirInvitacion = () => abrir(invitacion);
  const terminarTiempoLibre = () => { invitacion.dataset.obligatoria = ''; invitacion.close(); abrir(invitacion); };
  // La ventana obligatoria no se cierra con Esc
  invitacion.addEventListener('cancel', (e) => { if (invitacion.hasAttribute('data-obligatoria')) e.preventDefault(); });

  // Marcas de tiempo entre paginas (si el navegador bloquea el almacenamiento, cuenta solo esta pagina)
  const leer = (almacen, clave) => { try { return almacen.getItem(clave); } catch { return null; } };
  const guardar = (almacen, clave, valor) => { try { almacen.setItem(clave, valor); } catch { /* sin almacenamiento */ } };

  if (sesion) {
    // Con cuenta: el correo de la consulta ya lleva su nombre y correo
    const enlace = consulta?.querySelector('[data-consulta-correo]');
    if (enlace) {
      const cuerpo = `Hola, soy ${sesion.nombre} (${sesion.correo}). Vi la demo de ${enlace.dataset.producto} y me gustaría agendar una consulta para solicitar el producto.`;
      enlace.href += `&body=${encodeURIComponent(cuerpo)}`;
    }
    aviso.textContent = 'Te mostramos esta función en una consulta personalizada';
    // Recomendacion de agendar una consulta, una vez por visita
    if (!leer(sessionStorage, 'sulotec.consulta.sugerida')) {
      setTimeout(() => {
        if (invitacion.open || consulta.open) return;
        guardar(sessionStorage, 'sulotec.consulta.sugerida', '1');
        abrir(consulta);
      }, segundosConsulta * 1000);
    }
  } else if (conLimite) {
    let inicio = Number(leer(localStorage, 'sulotec.demo.inicio'));
    if (!inicio) { inicio = Date.now(); guardar(localStorage, 'sulotec.demo.inicio', String(inicio)); }
    const restante = inicio + limiteSegundos * 1000 - Date.now();
    if (restante <= 0) terminarTiempoLibre(); else setTimeout(terminarTiempoLibre, restante);
  } else if (!leer(sessionStorage, 'sulotec.demo.invitado')) {
    setTimeout(() => { guardar(sessionStorage, 'sulotec.demo.invitado', '1'); abrirInvitacion(); }, limiteSegundos * 1000);
  }

  let temporizadorAviso;
  const mostrarAviso = () => {
    aviso.hidden = false;
    clearTimeout(temporizadorAviso);
    temporizadorAviso = setTimeout(() => { aviso.hidden = true; }, 2400);
  };

  document.addEventListener('click', (e) => {
    const objetivo = e.target.closest('[data-bloqueado], [data-abrir-invitacion], [data-cerrar-invitacion], [data-abrir-consulta], [data-cerrar-consulta], [data-mostrar], [data-asesor], [data-evaluar]');
    if (!objetivo) return;

    if (objetivo.hasAttribute('data-abrir-invitacion')) { abrirInvitacion(); return; }
    if (objetivo.hasAttribute('data-cerrar-invitacion')) { invitacion.close(); return; }
    if (objetivo.hasAttribute('data-abrir-consulta')) { abrir(consulta); return; }
    if (objetivo.hasAttribute('data-cerrar-consulta')) { consulta.close(); return; }

    if (objetivo.hasAttribute('data-bloqueado')) {
      e.preventDefault();
      accionesBloqueadas += 1;
      if (accionesBloqueadas >= limiteAcciones) {
        accionesBloqueadas = 0;
        if (sesion) abrir(consulta); else abrirInvitacion();
      } else {
        mostrarAviso();
      }
      return;
    }

    // Seleccion de un elemento de una lista: muestra su panel y oculta los demas del mismo grupo
    if (objetivo.dataset.mostrar) {
      const grupo = objetivo.dataset.grupo;
      document.querySelectorAll(`[data-grupo="${grupo}"]`).forEach((b) => b.setAttribute('aria-pressed', String(b === objetivo)));
      document.querySelectorAll(`[data-grupo-panel="${grupo}"]`).forEach((p) => { p.hidden = p.id !== objetivo.dataset.mostrar; });
      return;
    }

    // MiRadar360: resaltar el recorrido del asesor elegido (otro clic lo desmarca)
    if (objetivo.dataset.asesor) {
      const mapa = document.querySelector('.mapa');
      const yaActivo = objetivo.getAttribute('aria-pressed') === 'true';
      document.querySelectorAll('[data-asesor]').forEach((b) => b.setAttribute('aria-pressed', 'false'));
      mapa.querySelectorAll('.ruta').forEach((r) => r.classList.remove('activa'));
      if (yaActivo) { mapa.classList.remove('atenuado'); return; }
      objetivo.setAttribute('aria-pressed', 'true');
      mapa.classList.add('atenuado');
      mapa.querySelector(`[data-ruta="${objetivo.dataset.asesor}"]`)?.classList.add('activa');
      return;
    }

    // Prevencion de Lavado de Activos: simular la evaluacion del cliente
    if (objetivo.hasAttribute('data-evaluar')) {
      const evaluacion = document.querySelector('[data-evaluacion]');
      if (evaluacion.dataset.estado === 'listo') { mostrarAviso(); return; }
      evaluacion.dataset.estado = 'evaluando';
      objetivo.disabled = true;
      setTimeout(() => { evaluacion.dataset.estado = 'listo'; objetivo.disabled = false; }, reducido ? 300 : 1800);
    }
  });

  // Respetar "reducir movimiento": detener las animaciones del mapa
  if (reducido) document.querySelectorAll('svg').forEach((s) => s.pauseAnimations?.());
});
