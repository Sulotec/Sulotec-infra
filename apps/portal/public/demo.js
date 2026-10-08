// Comportamiento de las demos publicas (/demo/...). Sin datos reales ni llamadas a servidores.
document.addEventListener('DOMContentLoaded', () => {
  const app = document.querySelector('.app');
  const dialogo = document.getElementById('invitacion');
  const aviso = document.querySelector('.aviso-bloqueo');
  const reducido = matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (!app || !dialogo) return;

  const limiteAcciones = Number(app.dataset.acciones) || 3;
  const limiteSegundos = Number(app.dataset.segundos) || 75;
  let accionesBloqueadas = 0;
  let invitacionMostrada = false;

  const abrirInvitacion = () => {
    if (dialogo.open) return;
    invitacionMostrada = true;
    dialogo.showModal();
  };

  // Invitacion: tras unos segundos de uso (una sola vez) o al tocar varias opciones bloqueadas
  setTimeout(() => { if (!invitacionMostrada) abrirInvitacion(); }, limiteSegundos * 1000);

  let temporizadorAviso;
  const mostrarAviso = () => {
    aviso.hidden = false;
    clearTimeout(temporizadorAviso);
    temporizadorAviso = setTimeout(() => { aviso.hidden = true; }, 2200);
  };

  document.addEventListener('click', (e) => {
    const objetivo = e.target.closest('[data-bloqueado], [data-abrir-invitacion], [data-cerrar-invitacion], [data-mostrar], [data-asesor], [data-evaluar]');
    if (!objetivo) return;

    if (objetivo.hasAttribute('data-abrir-invitacion')) { abrirInvitacion(); return; }
    if (objetivo.hasAttribute('data-cerrar-invitacion')) { dialogo.close(); return; }

    if (objetivo.hasAttribute('data-bloqueado')) {
      e.preventDefault();
      accionesBloqueadas += 1;
      if (accionesBloqueadas >= limiteAcciones) { accionesBloqueadas = 0; abrirInvitacion(); }
      else mostrarAviso();
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
