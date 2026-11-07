// Mis productos: marca en gris lo no contratado. Va en archivo aparte porque la CSP
// (script-src 'self') bloquea los scripts en linea.
// Productos contratados: la cuenta Sulotec trae en su token el rol `producto-<clave>` por cada producto;
// los demas quedan en gris con su demo. Los administradores universales de Sulotec tienen todo (lo marca cuenta.js).
document.addEventListener('DOMContentLoaded', () => {
  const s = window.sulotecCuenta?.sesion();
  const roles = Array.isArray(s?.roles) ? s.roles : [];
  const todo = roles.includes('administrador-general');
  document.querySelectorAll('[data-producto]').forEach((el) => {
    const contratado = todo || roles.includes(`producto-${el.dataset.producto}`);
    el.classList.toggle('bloqueado', !contratado);
    el.querySelectorAll('[data-abrir]').forEach((a) => { a.hidden = !contratado; });
    el.querySelectorAll('[data-no-contratado]').forEach((n) => { n.hidden = contratado; });
    // Productos privados (publico: false): solo se muestran a quien los tiene contratados
    if (el.dataset.publico === '0') el.hidden = !contratado;
  });
});
