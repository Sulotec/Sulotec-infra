/*
 * <indira-asistente>: Indira en sulotec.com. Sin dependencias, con Shadow DOM y sin inline (CSP script-src 'self').
 *
 * - El dibujo, las expresiones y el mapa unico de poses viven en /indira/titere.js (window.IndiraTitere).
 * - Dos modos:
 *     sulotec (por defecto): Indira animada con esqueleto (/indira/cuerpo.js, window.IndiraCuerpo), de la cintura
 *       para arriba dentro de la cabecera del chat. Desde 900 px un boton la pasa a cuerpo completo junto al panel
 *       y de vuelta; la eleccion se guarda. Si cuerpo.js no esta, usa el busto de siempre.
 *       Voz: los textos fijos que tienen audio en /indira/voz/voces.json (texto -> archivo) se dicen con su voz y la
 *       boca sigue el sonido. Con <meta name="indira-voz" content="URL del servicio de voz"> (o el atributo voz) dice
 *       ademas CUALQUIER texto, tambien las respuestas del modelo: frase por frase, pidiendo la siguiente mientras dice
 *       la actual (GET {voz}/v1/voz?texto=...). Boton "Voz" para silenciarla (se recuerda). Sin servicio: boca muda.
 *     producto: para los demas productos. Solo el chat y la carita redonda, quieta y mas pequena; sin cuerpo ni poses.
 *       Se elige con <indira-asistente modo="producto"> o con data-modo="producto" en la etiqueta de este script.
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
  var MODO_SCRIPT = (document.currentScript && document.currentScript.getAttribute('data-modo')) || '';
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
      this.producto = (this.getAttribute('modo') || MODO_SCRIPT) === 'producto';
      this.C = this.producto ? null : window.IndiraCuerpo || null;
      this.api = (this.getAttribute('api') || meta('indira-api') || '').replace(/\/+$/, '');
      this.vozBase = (this.getAttribute('voz') || meta('indira-voz') || '').replace(/\/+$/, '') || (meta('indira-voz') === '/' ? '/' : '');
      this.turno = 0;
      this.turnoActivo = false;
      this.yo = null;
      var raizSombra = this.attachShadow({ mode: 'open' });
      ['titere.css', 'widget.css'].forEach(function (f) {
        var l = document.createElement('link');
        l.rel = 'stylesheet'; l.href = BASE + f;
        raizSombra.appendChild(l);
      });
      var raiz = this.raiz = el('div', 'indira' + (this.producto ? ' indira-producto' : ''));
      raiz.setAttribute('role', 'complementary');
      raiz.setAttribute('aria-label', 'Indira, asistente de Sulotec');
      raizSombra.appendChild(raiz);

      this.burbuja = boton('indira-boton', '', 'Abrir Indira');
      this.burbuja.setAttribute('aria-haspopup', 'dialog');
      this.burbuja.setAttribute('aria-expanded', 'false');
      var marco = el('span', 'indira-marco');
      this.burbuja.appendChild(marco);
      raiz.appendChild(this.burbuja);
      this.avatar = T.crear(marco, { encuadre: 'cara', voz: false, sinMovimiento: this.producto });
      this.avatar.elemento.setAttribute('aria-hidden', 'true');

      var yo = this;
      this.burbuja.addEventListener('click', function () { yo.abre(); });
      this._esc = function (ev) {
        if (ev.key !== 'Escape') return;
        if (yo.panel) yo.cierra(); else if (yo.globo) yo.cierraGlobo('descarte');
      };
      document.addEventListener('keydown', this._esc);

      this.datos = Promise.all([cargaJson('invitado.json'), cargaJson('preguntas.json'), this.C ? cargaJson('voz/voces.json') : null]).then(function (r) {
        yo.invitado = r[0] || { saludo: 'Hola, soy Indira.', respuestas: [], libre: '' };
        yo.preguntas = r[1] || {};
        yo.voces = r[2] || {};
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

      /* Con IndiraCuerpo: dentro de la cabecera o, desde 900 px y si se eligio, de cuerpo completo junto al panel.
       * Sin el (o en modo producto): el titere de siempre; en modo producto, quieto. */
      var ancho = !this.producto && window.matchMedia('(min-width: 900px)').matches;
      var deCuerpo = !this.producto && !!this.C;
      var lado = this.lado = el('div', 'indira-lado');
      lado.setAttribute('aria-hidden', 'true');

      var cuerpo = el('div', 'indira-cuerpo');
      var cabeza = this.cabeza = el('div', 'indira-cabeza');
      var titulo = el('div', 'indira-titulo');
      var h = el('h2', '', 'Indira'); h.id = 'indira-titulo';
      titulo.appendChild(h);
      titulo.appendChild(el('p', '', 'Asistente de Sulotec · IA'));
      cabeza.appendChild(titulo);
      if (deCuerpo) {
        if (ancho) {
          var vb = this.botonVista = boton('indira-vista', '');
          vb.addEventListener('click', function () {
            var vista = yo.vista === 'completa' ? 'chat' : 'completa';
            guarda({ vista: vista });
            yo.montaCuerpo(vista);
          });
          cabeza.appendChild(vb);
        }
        this.montaCuerpo(ancho && leeGuardado().vista === 'completa' ? 'completa' : 'chat');
      } else {
        var figura = el('span', 'indira-marco indira-figura' + (ancho ? '' : ' indira-mini'));
        figura.setAttribute('aria-hidden', 'true');
        if (ancho) { lado.appendChild(figura); panel.classList.add('con-lado'); } else cabeza.insertBefore(figura, titulo);
        this.titere = T.crear(figura, { encuadre: ancho ? 'medio' : 'cara', etiqueta: 'Indira', sinMovimiento: this.producto });
        var bv = this.producto ? null : T.botonVoz(this.titere);
        if (bv) cabeza.appendChild(bv);
      }
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
        if (deCuerpo && (yo.vozBase || Object.keys(yo.voces).length)) yo.ponBotonVoz();
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
    /* Pone a Indira (el esqueleto) en la cabecera ('chat') o junto al panel ('completa'), sin perder su estado. */
    montaCuerpo(vista) {
      var yo = this;
      if (this.cuerpo) { this.cuerpo.callar(); this.cuerpo.destruir(); }
      if (this.figura) this.figura.remove();
      var completa = vista === 'completa';
      this.vista = vista;
      var figura = this.figura = el('span', 'indira-marco indira-figura ' + (completa ? 'indira-completa' : 'indira-encabezado'));
      figura.setAttribute('aria-hidden', 'true');
      if (completa) this.lado.appendChild(figura); else this.cabeza.insertBefore(figura, this.cabeza.firstChild);
      this.panel.classList.toggle('con-lado', completa);
      /* El cuerpo responde a los mismos llamados que el titere: expresion, hablar, callar y destruir. */
      var c = this.cuerpo = this.C.crear(figura, { encuadre: completa ? 'completo' : 'cabecera', etiqueta: 'Indira' });
      c.estado(this._estado || 'reposo');
      this.titere = {
        expresion: function (e) { c.expresion(e === 'reposo' ? null : e); },
        hablar: function (t) { return c.hablar(t); },
        callar: function () { if (yo.locutor) { yo.locutor.corta(); yo.locutor = null; } yo.bufferVoz = ''; c.callar(); },
        destruir: function () { c.destruir(); }
      };
      if (this.botonVista) {
        this.botonVista.textContent = completa ? 'Llevar al chat' : 'Cuerpo completo';
        this.botonVista.setAttribute('aria-pressed', completa ? 'true' : 'false');
        this.botonVista.setAttribute('aria-label', completa ? 'Mostrar a Indira dentro del chat' : 'Mostrar a Indira de cuerpo completo');
      }
    }
    /* ------- Voz ------- */
    conVoz() { return leeGuardado().voz !== false; }
    ponBotonVoz() {
      var yo = this, b = boton('indira-voz indira-vozpropia', '');
      function pinta() {
        var si = yo.conVoz();
        b.textContent = si ? '\ud83d\udd0a Voz' : '\ud83d\udd07 Voz';
        b.setAttribute('aria-pressed', si ? 'true' : 'false');
        b.setAttribute('aria-label', si ? 'Silenciar la voz de Indira' : 'Activar la voz de Indira');
      }
      b.addEventListener('click', function () {
        var si = !yo.conVoz();
        guarda({ voz: si });
        if (!si && yo.titere) yo.titere.callar();
        pinta();
      });
      pinta();
      this.cabeza.insertBefore(b, this.cabeza.querySelector('.indira-cerrar'));
    }
    vozViva() { return !!(this.vozBase && this.cuerpo && this.conVoz()); }
    urlVoz(frase) { return (this.vozBase === '/' ? '' : this.vozBase) + '/v1/voz?texto=' + encodeURIComponent(frase); }
    audioPara(url) {
      var a = new Audio();
      /* Otro origen: hace falta CORS para que el analizador de la boca pueda leer el sonido. */
      try { if (new URL(url, location.href).origin !== location.origin) a.crossOrigin = 'anonymous'; } catch (e) {}
      a.preload = 'auto';
      a.src = url;
      return a;
    }
    /* Corta un texto en frases para el servicio de voz: ni muy cortas (suenan entrecortadas) ni de mas de 380 letras. */
    frasesDe(texto) {
      var partes = String(texto).match(/[^\n]*?(?:[.!?\u2026]+(?=\s|$)|\n|$)\s*/g) || [], frases = [], acc = '';
      partes.forEach(function (p) {
        acc += p;
        if (acc.trim().length >= 24) { frases.push(acc); acc = ''; }
      });
      if (acc.trim()) { if (frases.length && acc.trim().length < 24) frases[frases.length - 1] += acc; else frases.push(acc); }
      var cortas = [];
      frases.forEach(function (f) {
        while (f.length > 380) {
          var i = f.lastIndexOf(', ', 380); if (i < 120) i = f.lastIndexOf(' ', 380);
          cortas.push(f.slice(0, i + 1)); f = f.slice(i + 1);
        }
        cortas.push(f);
      });
      return cortas.filter(function (f) { return /[\wáéíóúñ]/i.test(f); });
    }
    /*
     * Locutor: dice frases en orden. Mientras suena una, ya pide la siguiente (asi no hay silencios largos) y
     * solo una a la vez, para que el servicio las genere en orden. alFrase(f) avisa cuando empieza cada una.
     */
    crearLocutor(alFrase) {
      var yo = this, cola = [], actual = null, cerrado = false, cortado = false, termina;
      var listo = new Promise(function (ok) { termina = ok; });
      function prepara(f) { if (!f.el) f.el = yo.audioPara(f.url || yo.urlVoz(f.texto)); }
      function sigue() {
        if (cortado || actual) return;
        if (!cola.length) { if (cerrado) termina(); return; }
        actual = cola.shift(); prepara(actual);
        /* Pide las dos siguientes por adelantado: el servicio las atiende en orden y asi no hay silencios largos. */
        cola.slice(0, 2).forEach(prepara);
        if (alFrase) alFrase(actual);
        if (!yo.cuerpo) { cortado = true; termina(); return; }
        yo.cuerpo.hablarAudio(actual.el).then(function () { actual = null; sigue(); });
      }
      return {
        encola: function (f) { if (cortado) return; cola.push(f); if (!actual) sigue(); else if (cola.length <= 2) prepara(f); },
        cierra: function () { cerrado = true; if (!actual && !cola.length) termina(); },
        corta: function () { cortado = true; cola = []; termina(); },
        cerrado: function () { return cerrado || cortado; },
        listo: listo
      };
    }
    /* Dice un texto con su voz (audio fijo o servicio de voz): las palabras aparecen al ritmo del audio. */
    escribeConVoz(texto, fuentes) {
      var m = this.agrega('', 'ella'), mio = ++this.turno, yo = this, mostrado = '';
      m.setAttribute('aria-hidden', 'true');
      if (this.locutor) this.locutor.corta();
      var loc = this.locutor = this.crearLocutor(function (f) {
        if (mio !== yo.turno) return;
        var base = mostrado, palabras = f.texto.match(/\S+\s*/g) || [];
        mostrado += f.texto;
        m.textContent = base;
        function avanza() {
          if (mio !== yo.turno || !f.el.duration || !yo.mensajes) return;
          var n = Math.min(palabras.length, Math.ceil(palabras.length * f.el.currentTime / (f.el.duration * .92)));
          m.textContent = base + palabras.slice(0, n).join('');
          yo.mensajes.scrollTop = yo.mensajes.scrollHeight;
        }
        f.el.addEventListener('timeupdate', avanza);
        f.el.addEventListener('ended', function () { m.textContent = base + f.texto; });
      });
      fuentes.forEach(function (f) { loc.encola(f); });
      loc.cierra();
      return loc.listo.then(function () {
        if (yo.locutor === loc) yo.locutor = null;
        m.textContent = texto;
        m.removeAttribute('aria-hidden');
        if (mio === yo.turno) yo.anuncia(texto);
        if (yo.mensajes) yo.mensajes.scrollTop = yo.mensajes.scrollHeight;
        return m;
      });
    }
    /* Respuesta del modelo en pedazos: cada frase completa va al locutor apenas termina. */
    vozDelta(trozo, final) {
      /* Una respuesta nueva no se mezcla con lo que estaba diciendo: corta lo anterior y usa su propio locutor. */
      if (!this.locutor || !this.locutor.delta || this.locutor.cerrado()) {
        if (this.locutor) this.locutor.corta();
        if (this.cuerpo) this.cuerpo.callar();
        this.locutor = this.crearLocutor(null);
        this.locutor.delta = true;
        this.bufferVoz = '';
      }
      this.bufferVoz = (this.bufferVoz || '') + (trozo || '');
      var corte;
      while ((corte = this.bufferVoz.search(/[.!?\u2026:;\n]\s/)) >= 0) {
        var hasta = corte + 1;
        if (hasta < 24 && !final) { var otro = this.bufferVoz.slice(hasta).search(/[.!?\u2026:;\n]\s/); if (otro < 0) break; hasta += otro + 1; }
        var frase = this.bufferVoz.slice(0, hasta + 1);
        this.bufferVoz = this.bufferVoz.slice(hasta + 1);
        this.frasesDe(frase).forEach(function (f) { this.locutor.encola({ texto: f }); }, this);
      }
      if (final) {
        var yo = this, loc = this.locutor;
        this.frasesDe(this.bufferVoz).forEach(function (f) { loc.encola({ texto: f }); });
        this.bufferVoz = '';
        loc.cierra();
        loc.listo.then(function () { if (yo.locutor === loc) yo.locutor = null; });
      }
    }
    cierra() {
      clearTimeout(this._vuelta); this.quitaPose(); this.turno++;
      if (this.titere) { this.titere.callar(); this.titere.destruir(); this.titere = null; }
      this.cuerpo = this.figura = this.botonVista = this._estado = null;
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
      clearTimeout(this._vuelta);
      this._estado = e;
      if (this.cuerpo) {
        /* De cuerpo completo el gesto lo hace ella misma: sin poses sueltas. */
        var c = this.cuerpo;
        c.estado(e);
        if (e !== 'pensando') this._vuelta = setTimeout(function () { yo._estado = 'reposo'; if (yo.cuerpo) yo.cuerpo.estado('reposo'); }, VUELTA_MS);
        return;
      }
      if (this.titere) this.titere.expresion(def.expresion);
      if (!this.producto) this.muestraPose(e);
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
      this.T.animarPose(img, e);
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
      var archivo = this.voces && this.voces[texto];
      if (archivo && this.cuerpo && this.conVoz()) return this.escribeConVoz(texto, [{ texto: texto, url: BASE + 'voz/' + encodeURIComponent(archivo) }]);
      if (this.vozViva()) return this.escribeConVoz(texto, this.frasesDe(texto).map(function (f) { return { texto: f }; }));
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
          if (yo.vozViva()) yo.vozDelta(d.texto || '', false);
          else if (yo.titere) yo.titere.hablar(d.texto || '');
        } else if (tipo === 'expresion') {
          yo.estado(POR_EXPRESION[d.valor] || 'reposo');
        } else if (tipo === 'enlace') {
          yo.enlace(burbuja(), d.destino, d.etiqueta);
        } else if (tipo === 'fin') {
          terminado = true;
          if (yo.locutor && yo.vozViva()) yo.vozDelta('', true);
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
