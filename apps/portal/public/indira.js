/*
 * <indira-asistente>: Indira en sulotec.com. Sin dependencias, con Shadow DOM y sin inline (CSP script-src 'self').
 *
 * - El dibujo, las expresiones y el mapa unico de poses viven en /indira/titere.js (window.IndiraTitere).
 * - Sin sesion no se llama a la API: responde con textos fijos de /indira/invitado.json y ofrece "Entrar".
 * - Con sesion usa api-indira.sulotec.com: POST /v1/turnos y los eventos SSE del turno, leidos con fetch
 *   (EventSource no admite el encabezado Authorization). Contrato: openapi.json de Indira-Backend.
 * - El texto del modelo se pinta solo con textContent, sin Markdown. Los enlaces salen solo del evento
 *   `enlace` y de una lista cerrada de destinos.
 * - token() se pide solo con el panel abierto o con un turno en curso.
 */
(function () {
  'use strict';
  if (window.customElements.get('indira-asistente')) return;

  var BASE = '/indira/';
  var CLAVE = 'sulotec.indira.v1';
  var CLAVE_CONVERSACION = 'sulotec.indira.conversacion';
  var DIA = 864e5;
  var PANTALLA = /^\/[a-z0-9/_-]{0,63}$/;
  var DESTINOS = { 'mi-licencia': '/mi-licencia', 'mis-productos': '/mis-productos', demos: '/#soluciones', inicio: '/' };
  var ENTRADA_MS = 4000, GLOBO_MS = 12000, GUINO_MS = 1200, POSE_MS = 2800, VUELTA_MS = 3200;
  /* Errores de cobro o de licencia: Indira queda neutra, sin guino ni lagrimas. */
  var SERIOS = ['BOLSA_AGOTADA', 'SIN_LICENCIA', 'SUSPENDIDA', 'SOLO_LECTURA', 'SIN_EMPRESA', 'LIMITE_USUARIO', 'TOPE_DIARIO', 'COLA_LLENA', 'USUARIO_OCUPADO', 'TURNO_EN_TRAMITE', 'MENSAJE_INVALIDO', 'CUERPO_DEMASIADO_GRANDE'];
  /* Expresion que manda el servidor -> estado del titere. */
  var POR_EXPRESION = { reposo: 'reposo', feliz: 'gracias', pensando: 'pensando', sorpresa: 'sorpresa', duda: 'duda', triste: 'error', guino: 'broma', picara: 'broma', victoria: 'logro', llorando: 'error' };
  var FASES = { en_cola: 'En cola', pensando: 'Indira está pensando…', consultando: 'Indira está consultando…' };

  function el(tag, clase, texto) {
    var n = document.createElement(tag);
    if (clase) n.className = clase;
    if (texto) n.textContent = texto;
    return n;
  }
  function boton(clase, texto, etiqueta) {
    var b = el('button', clase, texto);
    b.type = 'button';
    if (etiqueta) b.setAttribute('aria-label', etiqueta);
    return b;
  }
  function uuid() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    var b = crypto.getRandomValues(new Uint8Array(16));
    b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
    var h = Array.prototype.map.call(b, function (x) { return (x + 256).toString(16).slice(1); }).join('');
    return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20);
  }
  function leeGuardado() {
    try { return JSON.parse(localStorage.getItem(CLAVE)) || {}; } catch (e) { return {}; }
  }
  function guarda(cambio) {
    var d = leeGuardado();
    for (var k in cambio) d[k] = cambio[k];
    try { localStorage.setItem(CLAVE, JSON.stringify(d)); } catch (e) {}
    return d;
  }
  function conversacion(valor) {
    try {
      if (valor === undefined) return sessionStorage.getItem(CLAVE_CONVERSACION);
      if (valor) sessionStorage.setItem(CLAVE_CONVERSACION, valor); else sessionStorage.removeItem(CLAVE_CONVERSACION);
    } catch (e) {}
    return null;
  }
  function cargaJson(nombre) {
    return fetch(BASE + nombre, { credentials: 'same-origin' })
      .then(function (r) { return r.ok ? r.json() : null; })
      .catch(function () { return null; });
  }
  function meta(nombre) {
    var m = document.querySelector('meta[name="' + nombre + '"]');
    return m ? m.content : '';
  }
  function cuenta() { return window.sulotecCuenta || null; }
  function conSesion() { var c = cuenta(); return !!(c && c.sesion && c.sesion()); }

  /* Lee un flujo SSE de fetch y llama a alEvento(tipo, datos, id). Termina al cerrarse el flujo. */
  function leeSse(respuesta, alEvento) {
    var lector = respuesta.body.getReader(), dec = new TextDecoder(), buf = '';
    function bloque(txt) {
      var tipo = 'message', datos = '', id = null;
      txt.split('\n').forEach(function (linea) {
        if (!linea || linea.charAt(0) === ':') return;
        var i = linea.indexOf(':'), campo = i < 0 ? linea : linea.slice(0, i), valor = i < 0 ? '' : linea.slice(i + 1).replace(/^ /, '');
        if (campo === 'event') tipo = valor;
        else if (campo === 'data') datos += (datos ? '\n' : '') + valor;
        else if (campo === 'id') id = valor;
      });
      if (!datos && tipo === 'message') return;
      var obj = {};
      try { obj = datos ? JSON.parse(datos) : {}; } catch (e) { return; }
      alEvento(tipo, obj, id);
    }
    function sigue() {
      return lector.read().then(function (r) {
        if (r.done) return;
        buf += dec.decode(r.value, { stream: true }).replace(/\r\n?/g, '\n');
        var corte;
        while ((corte = buf.indexOf('\n\n')) >= 0) {
          bloque(buf.slice(0, corte));
          buf = buf.slice(corte + 2);
        }
        return sigue();
      });
    }
    return sigue();
  }

  class IndiraAsistente extends HTMLElement {
    connectedCallback() {
      if (this._listo) return;
      this._listo = true;
      var T = window.IndiraTitere;
      if (!T || location.pathname.indexOf('/cuenta/') === 0) { this.hidden = true; return; }
      this.T = T;
      this.api = (this.getAttribute('api') || meta('indira-api') || '').replace(/\/+$/, '');
      this.turno = 0;
      this.turnoActivo = false;
      this.yo = null;
      var raizSombra = this.attachShadow({ mode: 'open' });
      ['titere.css', 'widget.css'].forEach(function (f) {
        var l = document.createElement('link');
        l.rel = 'stylesheet'; l.href = BASE + f;
        raizSombra.appendChild(l);
      });
      var raiz = this.raiz = el('div', 'indira');
      raiz.setAttribute('role', 'complementary');
      raiz.setAttribute('aria-label', 'Indira, asistente de Sulotec');
      raizSombra.appendChild(raiz);

      this.burbuja = boton('indira-boton', '', 'Abrir Indira');
      this.burbuja.setAttribute('aria-haspopup', 'dialog');
      this.burbuja.setAttribute('aria-expanded', 'false');
      var marco = el('span', 'indira-marco');
      this.burbuja.appendChild(marco);
      raiz.appendChild(this.burbuja);
      this.avatar = T.crear(marco, { encuadre: 'cara', voz: false });
      this.avatar.elemento.setAttribute('aria-hidden', 'true');

      var yo = this;
      this.burbuja.addEventListener('click', function () { yo.abre(); });
      this._esc = function (ev) {
        if (ev.key !== 'Escape') return;
        if (yo.panel) yo.cierra(); else if (yo.globo) yo.cierraGlobo('descarte');
      };
      document.addEventListener('keydown', this._esc);

      this.datos = Promise.all([cargaJson('invitado.json'), cargaJson('preguntas.json')]).then(function (r) {
        yo.invitado = r[0] || { saludo: 'Hola, soy Indira.', respuestas: [], libre: '' };
        yo.preguntas = r[1] || {};
      });

      /* Entra a los 4 s, con guino de 1,2 s. Sin movimiento si el usuario lo pidio (lo resuelve el CSS). */
      this._entrada = setTimeout(function () {
        raiz.classList.add('indira-visible');
        yo.avatar.expresion('guino');
        setTimeout(function () { if (!yo.panel) yo.avatar.expresion('reposo'); }, GUINO_MS);
        yo.datos.then(function () { yo.programaPregunta(); });
      }, ENTRADA_MS);
    }

    disconnectedCallback() {
      clearTimeout(this._entrada);
      document.removeEventListener('keydown', this._esc);
    }

    /* ------- Pregunta proactiva: texto fijo, sin modelo y sin costo ------- */
    programaPregunta() {
      var ruta = location.pathname.replace(/\/+$/, '') || '/';
      var p = this.preguntas[ruta] || this.preguntas['*'];
      var d = leeGuardado(), ahora = Date.now();
      if (!p || this.panel) return;
      if (d.apagada || (d.silencioHasta && d.silencioHasta > ahora) || (d.ultima && ahora - d.ultima < DIA)) return;
      if ((d.descartadas || []).indexOf(p.id) >= 0) return;
      try { if (sessionStorage.getItem('sulotec.indira.preguntada')) return; } catch (e) {}
      var yo = this;
      (function intenta(veces) {
        if (yo.panel || veces > 20) return;
        var activo = document.activeElement;
        var escribiendo = activo && (/^(INPUT|TEXTAREA|SELECT)$/.test(activo.tagName) || activo.isContentEditable);
        if (document.hidden || document.querySelector('dialog[open]') || escribiendo) { setTimeout(function () { intenta(veces + 1); }, 3000); return; }
        yo.muestraGlobo(p);
      })(0);
    }
    muestraGlobo(p) {
      var yo = this;
      guarda({ ultima: Date.now() });
      try { sessionStorage.setItem('sulotec.indira.preguntada', '1'); } catch (e) {}
      var g = this.globo = el('div', 'indira-globo');
      g.setAttribute('role', 'status');
      g.appendChild(el('p', '', p.texto));
      var x = boton('indira-cerrar', '×', 'Cerrar pregunta');
      x.addEventListener('click', function () { yo.cierraGlobo('descarte'); yo.burbuja.focus(); });
      g.appendChild(x);
      var fila = el('div', 'indira-sugerencias');
      (p.opciones || []).forEach(function (o) {
        var b = boton('', o);
        b.addEventListener('click', function () { yo.cierraGlobo('usada'); yo.abre(); yo.respuestaFija(o); });
        fila.appendChild(b);
      });
      g.appendChild(fila);
      var no = boton('indira-enlace', 'No volver a preguntar');
      no.addEventListener('click', function () { guarda({ apagada: true }); yo.cierraGlobo('usada'); yo.burbuja.focus(); });
      g.appendChild(no);
      g._id = p.id;
      this.raiz.insertBefore(g, this.burbuja);
      /* Desaparece a los 12 s, con pausa mientras el cursor o el foco estan encima. */
      var resta = GLOBO_MS, desde = Date.now(), t = 0;
      function corre() { desde = Date.now(); t = setTimeout(function () { yo.cierraGlobo('tiempo'); }, resta); }
      function pausa() { clearTimeout(t); resta -= Date.now() - desde; }
      g.addEventListener('mouseenter', pausa); g.addEventListener('focusin', pausa);
      g.addEventListener('mouseleave', corre); g.addEventListener('focusout', corre);
      this._tGlobo = function () { clearTimeout(t); };
      corre();
    }
    cierraGlobo(motivo) {
      var g = this.globo;
      if (!g) return;
      if (this._tGlobo) this._tGlobo();
      g.remove();
      this.globo = null;
      if (motivo === 'descarte') {
        var d = leeGuardado(), descartadas = (d.descartadas || []).concat(g._id), seguidos = (d.seguidos || 0) + 1;
        var cambio = { descartadas: descartadas, seguidos: seguidos };
        if (seguidos >= 2) { cambio.silencioHasta = Date.now() + 30 * DIA; cambio.seguidos = 0; }
        guarda(cambio);
      } else if (motivo === 'usada') {
        guarda({ seguidos: 0 });
      }
    }

    /* ------- Panel ------- */
    abre() {
      if (this.panel) return;
      this.cierraGlobo('usada');
      var yo = this, T = this.T;
      this.burbuja.hidden = true;
      this.burbuja.setAttribute('aria-expanded', 'true');
      this.avatar.pausar();
      var panel = this.panel = el('div', 'indira-panel');
      panel.setAttribute('role', 'dialog');
      panel.setAttribute('aria-modal', 'false');
      panel.setAttribute('aria-labelledby', 'indira-titulo');

      /* Desde 900 px Indira va de cintura para arriba junto al panel; en pantallas menores, en la cabecera. */
      var ancho = window.matchMedia('(min-width: 900px)').matches;
      var lado = el('div', 'indira-lado');
      lado.setAttribute('aria-hidden', 'true');
      var figura = el('span', 'indira-marco indira-figura' + (ancho ? '' : ' indira-mini'));
      figura.setAttribute('aria-hidden', 'true');
      if (ancho) lado.appendChild(figura);
      this.titere = T.crear(figura, { encuadre: ancho ? 'medio' : 'cara', etiqueta: 'Indira' });

      var cuerpo = el('div', 'indira-cuerpo');
      var cabeza = this.cabeza = el('div', 'indira-cabeza');
      if (!ancho) cabeza.appendChild(figura);
      var titulo = el('div', 'indira-titulo');
      var h = el('h2', '', 'Indira'); h.id = 'indira-titulo';
      titulo.appendChild(h);
      titulo.appendChild(el('p', '', 'Asistente de Sulotec · IA'));
      cabeza.appendChild(titulo);
      var bv = T.botonVoz(this.titere);
      if (bv) cabeza.appendChild(bv);
      var x = boton('indira-cerrar', '×', 'Cerrar conversación');
      x.addEventListener('click', function () { yo.cierra(); });
      cabeza.appendChild(x);

      this.mensajes = el('div', 'indira-mensajes');
      this.anuncio = el('div', 'indira-oculto');
      this.anuncio.setAttribute('aria-live', 'polite');
      var pie = el('div', 'indira-pie');
      this.chips = el('div', 'indira-sugerencias');
      pie.appendChild(this.chips);
      var f = el('form', 'indira-form');
      var ta = this.entrada = el('textarea');
      ta.rows = 1;
      ta.maxLength = 2000;
      ta.placeholder = 'Escríbele a Indira';
      ta.setAttribute('aria-label', 'Mensaje para Indira');
      this.envio = el('button', '', 'Enviar'); this.envio.type = 'submit';
      f.appendChild(ta); f.appendChild(this.envio);
      f.addEventListener('submit', function (ev) {
        ev.preventDefault();
        var t = ta.value.trim();
        if (!t || yo.envio.disabled) return;
        ta.value = '';
        yo.envia(t);
      });
      ta.addEventListener('keydown', function (ev) {
        if (ev.key === 'Enter' && !ev.shiftKey && !ev.isComposing) { ev.preventDefault(); f.requestSubmit(); }
      });
      pie.appendChild(f);
      this.nota = el('p', 'indira-nota');
      pie.appendChild(this.nota);

      cuerpo.appendChild(cabeza); cuerpo.appendChild(this.mensajes); cuerpo.appendChild(this.anuncio); cuerpo.appendChild(pie);
      panel.appendChild(lado); panel.appendChild(cuerpo);
      this.raiz.appendChild(panel);
      this.estado('saludo');
      ta.focus();

      this.datos.then(function () {
        if (!yo.panel) return;
        yo.pintaChips();
        if (!conSesion()) {
          yo.nota.textContent = 'Sin sesión te respondo con información general. Para consultar tu empresa, entra con tu cuenta.';
          yo.escribe(yo.invitado.saludo);
          return;
        }
        yo.nota.textContent = 'Conversas con una IA. Las respuestas pueden equivocarse.';
        yo.escribe('Hola, soy Indira. ¿En qué te ayudo?');
        yo.pide('/v1/yo').then(function (r) {
          if (!yo.panel || !r.ok) return;
          yo.yo = r.datos;
          var n = r.datos && r.datos.tarifa && r.datos.tarifa.tokens_por_mensaje;
          if (n) yo.nota.textContent = 'Conversas con una IA. Cada mensaje que escribes consume ' + n + (n === 1 ? ' token' : ' tokens') + ' de tu licencia Indira; los botones son gratis.';
        });
      });
    }
    cierra() {
      clearTimeout(this._vuelta); this.quitaPose(); this.turno++;
      if (this.titere) { this.titere.callar(); this.titere.destruir(); this.titere = null; }
      if (this.panel) { this.panel.remove(); this.panel = this.mensajes = this.cabeza = this.envio = this.anuncio = this.entrada = null; }
      this.burbuja.hidden = false;
      this.burbuja.setAttribute('aria-expanded', 'false');
      this.avatar.reanudar();
      this.burbuja.focus();
    }
    pintaChips() {
      var yo = this;
      this.chips.textContent = '';
      (this.invitado.respuestas || []).slice(0, 3).forEach(function (r) {
        var b = boton('', r.pregunta);
        b.addEventListener('click', function () { yo.respuestaFija(r.pregunta); });
        yo.chips.appendChild(b);
      });
    }

    /* ------- Estados del titere ------- */
    estado(e) {
      var def = this.T.ESTADOS[e] || this.T.ESTADOS.reposo, yo = this;
      if (this.titere) this.titere.expresion(def.expresion);
      this.muestraPose(e);
      clearTimeout(this._vuelta);
      if (e !== 'pensando') this._vuelta = setTimeout(function () { if (yo.titere) yo.titere.expresion('reposo'); }, VUELTA_MS);
    }
    quitaPose() {
      clearTimeout(this._tPose);
      if (this.pose) { this.pose.remove(); this.pose = null; }
    }
    muestraPose(e) {
      this.quitaPose();
      var ruta = this.T.rutaPose(BASE, e), yo = this;
      if (!ruta || !this.cabeza) return;
      var img = this.pose = el('img', 'indira-pose');
      img.alt = ''; img.src = ruta; img.decoding = 'async';
      this.cabeza.insertBefore(img, this.cabeza.querySelector('.indira-titulo'));
      this._tPose = setTimeout(function () { yo.quitaPose(); }, POSE_MS);
    }

    /* ------- Mensajes ------- */
    agrega(texto, quien) {
      var m = el('div', 'indira-msj ' + quien, texto);
      this.mensajes.appendChild(m);
      this.mensajes.scrollTop = this.mensajes.scrollHeight;
      return m;
    }
    anuncia(texto) { if (this.anuncio) this.anuncio.textContent = texto; }
    /* Texto fijo con efecto de escritura; la boca lo sigue. */
    escribe(texto) {
      var m = this.agrega('', 'ella'), palabras = String(texto).match(/\S+\s*/g) || [], i = 0, mio = ++this.turno, yo = this;
      m.setAttribute('aria-hidden', 'true');
      return new Promise(function (listo) {
        (function sigue() {
          if (mio !== yo.turno || !yo.titere) { m.textContent = texto; m.removeAttribute('aria-hidden'); listo(m); return; }
          if (i >= palabras.length) { m.removeAttribute('aria-hidden'); yo.anuncia(texto); listo(m); return; }
          var w = palabras[i++];
          m.textContent += w;
          yo.mensajes.scrollTop = yo.mensajes.scrollHeight;
          yo.titere.hablar(w);
          setTimeout(sigue, 20 + w.length * 38);
        })();
      });
    }
    enlace(contenedor, destino, etiqueta) {
      var ruta = DESTINOS[destino];
      if (!ruta || contenedor.querySelector('a[href="' + ruta + '"]')) return;
      var a = el('a', 'indira-ir', etiqueta || 'Abrir');
      a.href = ruta;
      contenedor.appendChild(a);
    }
    botonEntrar(contenedor) {
      var c = cuenta();
      if (!c || !c.ir) {
        var a = el('a', 'indira-ir', 'Solicitar acceso');
        a.href = '/#contacto';
        contenedor.appendChild(a);
        return;
      }
      var b = boton('indira-ir', 'Entrar');
      b.addEventListener('click', function () { c.ir(); });
      contenedor.appendChild(b);
    }
    respuestaFija(pregunta) {
      var r = (this.invitado.respuestas || []).filter(function (x) { return x.pregunta === pregunta; })[0];
      if (!r || !this.panel) return;
      if (this.turnoActivo) return;
      this.titere.callar();
      this.agrega(pregunta, 'yo');
      var yo = this, sesion = conSesion();
      this.estado(r.estado || 'reposo');
      this.escribe(sesion && r.textoConSesion ? r.textoConSesion : r.texto).then(function (m) {
        if (r.enlace) yo.enlace(m, r.enlace.destino, r.enlace.etiqueta);
        if (!sesion && r.entrar) yo.botonEntrar(m);
      });
    }

    /* ------- API ------- */
    pide(ruta, opciones) {
      var yo = this, c = cuenta();
      if (!this.api || !c) return Promise.resolve({ ok: false, error: 'SIN_SESION' });
      return c.token().then(function (tk) {
        if (!tk) return { ok: false, error: 'SIN_SESION' };
        opciones = opciones || {};
        var h = opciones.headers || {};
        h.Authorization = 'Bearer ' + tk;
        opciones.headers = h;
        opciones.credentials = 'omit';
        opciones.cache = 'no-store';
        return fetch(yo.api + ruta, opciones).then(function (r) {
          if (opciones.flujo && r.ok) return { ok: true, respuesta: r };
          return r.json().catch(function () { return {}; }).then(function (d) {
            return r.ok ? { ok: true, datos: d } : { ok: false, estado: r.status, error: d.error || ('HTTP_' + r.status), mensaje: d.mensaje };
          });
        });
      }).catch(function () { return { ok: false, error: 'RED' }; });
    }
    ocupado(si) {
      this.turnoActivo = si;
      if (this.envio) this.envio.disabled = si;
    }
    falla(codigo, mensaje, contenedor) {
      var serio = SERIOS.indexOf(codigo) >= 0;
      this.estado(serio ? 'serio' : 'error');
      var texto = mensaje || (codigo === 'RED' ? 'No pude conectarme. Revisa tu conexión e inténtalo otra vez.' : 'No pude responder esta vez. Inténtalo de nuevo en un momento.');
      var m = contenedor || this.agrega('', 'ella aviso');
      m.textContent = texto;
      m.classList.add('aviso');
      m.removeAttribute('aria-hidden');
      this.anuncia(texto);
      if (codigo === 'SIN_SESION') this.botonEntrar(m);
      if (codigo === 'BOLSA_AGOTADA' || codigo === 'SIN_LICENCIA' || codigo === 'SUSPENDIDA') this.enlace(m, 'mi-licencia', 'Ver mi licencia');
    }
    envia(texto) {
      if (!this.titere) return;
      this.titere.callar();
      this.turno++;
      this.agrega(texto, 'yo');
      if (!conSesion()) {
        var yo0 = this;
        this.estado('reposo');
        this.escribe(this.invitado.libre || 'Para conversar conmigo necesitas entrar con tu cuenta de Sulotec. No hay registro libre.').then(function (m) { yo0.botonEntrar(m); });
        return;
      }
      var yo = this, mio = this.turno;
      var pantalla = PANTALLA.test(location.pathname) ? location.pathname : null;
      var cuerpo = { mensaje: texto, pantalla: pantalla, conversacion_id: conversacion() || null };
      var clave = uuid();
      this.ocupado(true);
      this.estado('pensando');
      var espera = el('div', 'indira-escribe', FASES.pensando);
      espera.setAttribute('aria-hidden', 'true');
      this.mensajes.appendChild(espera);
      var envio = function (intento) {
        return yo.pide('/v1/turnos', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Idempotency-Key': clave },
          body: JSON.stringify(cuerpo)
        }).then(function (r) {
          /* Un corte de red se reintenta una vez con la misma clave: el servidor no cobra dos veces. */
          if (!r.ok && r.error === 'RED' && intento < 1) return envio(intento + 1);
          return r;
        });
      };
      envio(0).then(function (r) {
        if (mio !== yo.turno || !yo.panel) return;
        if (!r.ok) {
          espera.remove(); yo.ocupado(false);
          if (r.error === 'NO_ENCONTRADO' && cuerpo.conversacion_id) conversacion(null);
          yo.falla(r.error, r.mensaje);
          return;
        }
        if (r.datos.conversacion_id) conversacion(r.datos.conversacion_id);
        yo.sigueTurno(r.datos.turno_id, mio, espera);
      });
    }
    sigueTurno(turnoId, mio, espera) {
      var yo = this, ultimo = null, texto = '', terminado = false, cortes = 0, m = null;
      function burbuja() {
        if (!m) { espera.remove(); m = yo.agrega('', 'ella'); m.setAttribute('aria-hidden', 'true'); }
        return m;
      }
      function alEvento(tipo, d, id) {
        if (id) ultimo = id;
        if (mio !== yo.turno || !yo.panel) return;
        if (tipo === 'estado') {
          espera.textContent = d.fase === 'en_cola' && d.posicion ? 'En cola: hay ' + d.posicion + ' antes que tú' : (FASES[d.fase] || FASES.pensando);
        } else if (tipo === 'reinicio') {
          texto = '';
          if (m) m.textContent = '';
          if (yo.titere) yo.titere.callar();
        } else if (tipo === 'delta') {
          texto += d.texto || '';
          burbuja().textContent = texto;
          yo.mensajes.scrollTop = yo.mensajes.scrollHeight;
          if (yo.titere) yo.titere.hablar(d.texto || '');
        } else if (tipo === 'expresion') {
          yo.estado(POR_EXPRESION[d.valor] || 'reposo');
        } else if (tipo === 'enlace') {
          yo.enlace(burbuja(), d.destino, d.etiqueta);
        } else if (tipo === 'fin') {
          terminado = true;
          var b = burbuja();
          b.removeAttribute('aria-hidden');
          yo.anuncia(texto);
          if (d.expresion) yo.estado(POR_EXPRESION[d.expresion] || 'reposo');
          if (d.truncado) b.appendChild(el('span', 'indira-detalle', 'La respuesta quedó incompleta.'));
          if (d.nivel_tokens && /bajo|agotad|critic/i.test(d.nivel_tokens)) {
            var aviso = el('span', 'indira-detalle', 'Te quedan pocos tokens en la licencia Indira.');
            b.appendChild(aviso);
            yo.enlace(b, 'mi-licencia', 'Ver mi licencia');
          }
          if (d.mensaje_id) yo.votos(b, d.mensaje_id);
          yo.ocupado(false);
        } else if (tipo === 'error') {
          terminado = true;
          espera.remove();
          var t = d.mensaje || '';
          if (d.reembolsado) t += (t ? ' ' : '') + 'No se descontó ningún token.';
          yo.falla(d.codigo, t, m);
          yo.ocupado(false);
        }
      }
      function escucha() {
        var h = { Accept: 'text/event-stream' };
        if (ultimo) h['Last-Event-ID'] = ultimo;
        return yo.pide('/v1/turnos/' + encodeURIComponent(turnoId) + '/eventos', { headers: h, flujo: true }).then(function (r) {
          if (!r.ok) throw r;
          return leeSse(r.respuesta, alEvento);
        }).then(function () {
          if (!terminado) throw { error: 'CORTE' };
        }).catch(function (err) {
          if (terminado || mio !== yo.turno || !yo.panel) return;
          if (err && err.error && err.error !== 'RED' && err.error !== 'CORTE') { espera.remove(); yo.falla(err.error, err.mensaje, m); yo.ocupado(false); return; }
          /* Se corto el tunel: reconecta con Last-Event-ID hasta 3 veces, y luego pregunta el estado. */
          if (++cortes <= 3) return new Promise(function (ok) { setTimeout(ok, 800 * cortes); }).then(escucha);
          return yo.pide('/v1/turnos/' + encodeURIComponent(turnoId)).then(function (r) {
            if (mio !== yo.turno || !yo.panel) return;
            espera.remove();
            if (r.ok && r.datos.estado === 'FIN' && r.datos.respuesta) {
              alEvento('reinicio', {}); alEvento('delta', { texto: r.datos.respuesta });
              alEvento('fin', { mensaje_id: r.datos.mensaje_id, expresion: r.datos.expresion, nivel_tokens: r.datos.nivel_tokens });
            } else {
              yo.falla('RED', null, m); yo.ocupado(false);
            }
          });
        });
      }
      escucha();
    }
    votos(contenedor, mensajeId) {
      var yo = this, fila = el('span', 'indira-votos');
      [[1, '👍', 'Me sirvió'], [-1, '👎', 'No me sirvió']].forEach(function (v) {
        var b = boton('', v[1], v[2]);
        b.addEventListener('click', function () {
          fila.textContent = 'Gracias por tu opinión.';
          yo.pide('/v1/mensajes/' + encodeURIComponent(mensajeId) + '/feedback', {
            method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ valor: v[0] })
          });
        });
        fila.appendChild(b);
      });
      contenedor.appendChild(fila);
    }
  }

  window.customElements.define('indira-asistente', IndiraAsistente);
  if (!document.querySelector('indira-asistente')) {
    var poner = function () { document.body.appendChild(document.createElement('indira-asistente')); };
    if (document.body) poner(); else document.addEventListener('DOMContentLoaded', poner);
  }
})();
