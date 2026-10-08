// Al entrar o recargar, la pagina siempre empieza en la portada:
// el navegador no restaura la posicion anterior ni salta a un #ancla de la direccion.
if ('scrollRestoration' in history) history.scrollRestoration = 'manual';
if (location.hash) history.replaceState(null, '', location.pathname + location.search);
window.scrollTo(0, 0);

// Los enlaces internos (#soluciones, #contacto, ...) bajan con desplazamiento suave
// sin dejar el #ancla en la direccion.
document.addEventListener('click', (evento) => {
  const enlace = evento.target.closest('a[href^="#"]');
  if (!enlace) return;
  const destino = document.getElementById(enlace.getAttribute('href').slice(1));
  if (!destino) return;
  evento.preventDefault();
  const suave = !matchMedia('(prefers-reduced-motion: reduce)').matches;
  destino.scrollIntoView({ behavior: suave ? 'smooth' : 'auto' });
});
