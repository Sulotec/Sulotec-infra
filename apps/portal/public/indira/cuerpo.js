/*
 * Indira de cuerpo completo, con esqueleto. Sin dependencias, sin inline ni eval: cumple script-src 'self'.
 * Necesita cuerpo-trazos.js (en la demo: indira-cuerpo-trazos.js) (generado desde Figma INdira, frames 1:48 y 9:240).
 *
 *   var c = IndiraCuerpo.crear(contenedor, { encuadre: 'completo' | 'medio' });
 *   c.gesto('saludo');  c.expresion('feliz');  c.hablar('Hola, soy Indira');  c.mirar(.5, -.2);
 *   c.hablarAudio(new Audio('voz/hola.mp3'))  -> habla con un audio real: la boca sigue su volumen.
 *
 * Cabeza, pelo, piernas, falda y rasgos son los trazos de Figma. El torso sin mangas y los brazos
 * (manga, antebrazo y mano relajada) estan dibujados aqui para poder doblarlos; la mano abierta es la de Figma.
 */
(function (global) {
  'use strict';

  var T = global.IndiraCuerpoTrazos;
  var NS = 'http://www.w3.org/2000/svg';
  var PIEL = '#F2D2BD', PIEL_SOMBRA = '#E8BAB2', ROSA = '#DEA3A7', LABIO = '#B57880', BOCA = '#7A3B47',
      AZUL = '#A4C6FF', AZUL_SOMBRA = '#92B0E3', CEJA = '#251608';

  /* ------- Proporciones (coordenadas del Frame 5, 840 x 2719) ------- */
  var CUELLO = [434, 560], PIES = [432, 2660];
  var HOMBRO_I = [266, 668], HOMBRO_D = [614, 668];
  var BRAZO = 282, ANTEBRAZO = 240;
  var OJO_I = [339, 343], OJO_D = [511, 343], BOCA_C = [426, 441];
  var ENCUADRES = { completo: '-80 -160 1000 2880', medio: '-40 -40 920 1300', cabecera: '20 -30 820 910', busto: '80 20 680 860' };
  /* Altura de los ojos dentro de cada encuadre: de ahi se mide hacia donde mirar al cursor. */
  var OJOS = { completo: .18, medio: .3, cabecera: .4, busto: .4 };

  var TORSO = 'M380 548C380 538 384 534 392 534L478 534C486 534 490 538 490 548L490 568C492 596 520 610 566 610C612 608 660 616 666 652' +
    'C670 690 656 744 648 796C640 862 630 960 622 1018C618 1040 600 1046 560 1048C500 1051 380 1050 300 1036C298 960 294 880 288 806' +
    'C282 750 214 708 214 662C216 622 242 610 300 608C348 606 366 600 374 580Z';
  /* Brazo izquierdo (el de la izquierda de la pantalla), con la articulacion en 0,0 y hacia +y. +x = hacia el cuerpo. */
  var MANGA = 'M-53 6C-56 -52 53 -56 53 2L46 ' + BRAZO + 'C34 ' + (BRAZO + 16) + ' -36 ' + (BRAZO + 16) + ' -47 ' + BRAZO + 'Z';
  var PLIEGUE = 'M-30 ' + (BRAZO - 40) + 'C-10 ' + (BRAZO - 30) + ' 12 ' + (BRAZO - 30) + ' 30 ' + (BRAZO - 44);
  var ANTE = 'M-39 -6C-40 -46 39 -46 39 -6L29 ' + ANTEBRAZO + 'C23 ' + (ANTEBRAZO + 14) + ' -23 ' + (ANTEBRAZO + 14) + ' -30 ' + ANTEBRAZO + 'Z';
  var CODO = 'M-31 -4C-17 12 12 14 31 -2C24 26 -21 28 -31 -4Z';
  var MANO = 'M-27 -4C-32 30 -34 74 -27 104C-23 132 -10 145 5 143C20 141 28 126 30 104C32 84 32 64 32 48' +
    'C42 58 56 64 62 56C66 47 53 31 38 15C33 8 31 0 29 -6Z';
  var DEDOS = ['M-9 76C-9 92 -8 108 -6 124', 'M10 78C11 94 12 108 13 120'];
  var CABELLO_PIVOTE = 500;

  /* ------- Bocas parametricas: ancho, comisuras, labio de arriba, fondo y cuanto se ven los dientes ------- */
  var BOCAS = {
    figma:    { w: 24, c: 0, up: 0, dn: 25, di: 1 },     /* Vector 38 de Figma */
    sonrisa:  { w: 21, c: -5, up: 3, dn: 7, di: 0 },
    feliz:    { w: 28, c: -3, up: -1, dn: 30, di: .7 },
    o:        { w: 12, c: 2, up: -9, dn: 17, di: 0 },
    pensando: { w: 13, c: 3, up: 1, dn: 5, di: 0 },
    triste:   { w: 17, c: 7, up: -3, dn: 2, di: 0 },
    a: { w: 21, c: 0, up: -3, dn: 30, di: .45 }, e: { w: 25, c: -1, up: -1, dn: 20, di: .65 },
    i: { w: 25, c: -2, up: 0, dn: 13, di: .95 }, oo: { w: 13, c: 1, up: -7, dn: 22, di: 0 },
    u: { w: 10, c: 1, up: -3, dn: 12, di: 0 }, m: { w: 20, c: -1, up: 1, dn: 3, di: 0 }
  };

  /* Expresiones: boca, ojos felices (arcos de Figma), cejas [izq, der], mirada fija y giro de cabeza. */
  var EXPRESIONES = {
    reposo:    { boca: 'figma' },
    sonrie:    { boca: 'sonrisa' },
    feliz:     { boca: 'feliz', felices: [1, 1], cejas: [-8, -8], rubor: .8 },
    guino:     { boca: 'sonrisa', felices: [0, 1], cejas: [-6, 2], giro: 3, rubor: .7 },
    sorpresa:  { boca: 'o', cejas: [-18, -18], ojo: 1.08 },
    pensando:  { boca: 'pensando', cejas: [-4, -12], mirada: [.8, -.8], giro: 4 },
    duda:      { boca: 'pensando', cejas: [-14, 4], mirada: [-.6, -.5], giro: -4 },
    triste:    { boca: 'triste', cejas: [-2, -2], tristes: 1, mirada: [0, .7], giro: -3, rubor: .7 }
  };

  /*
   * Gestos: angulos de cada brazo. h = hombro, c = codo, m = mano (grados; positivo = hacia afuera).
   * mano: 'r' relajada o 'a' abierta. delante: el antebrazo pasa por delante de la manga.
   * osc: [articulacion, amplitud, velocidad] para un vaiven propio del gesto.
   */
  var GESTOS = {
    reposo:    { i: { h: 7, c: -8, m: 0 }, d: { h: 7, c: -8, m: 0 }, expr: 'reposo' },
    saludo:    { i: { h: 140, c: 38, m: 0, mano: 'a', osc: ['c', 16, 9] }, d: { h: 6, c: -10, m: 0 }, expr: 'feliz', cabeza: 4 },
    presentar: { i: { h: 40, c: -30, m: -40, mano: 'a' }, d: { h: 7, c: -8, m: 0 }, expr: 'sonrie', cabeza: 3, mira: [-.6, 0] },
    explicar:  { i: { h: 24, c: -34, m: -62, mano: 'a', osc: ['c', 8, 3.1] }, d: { h: 22, c: -30, m: -58, mano: 'a', osc: ['c', 8, 2.6] }, expr: 'sonrie' },
    pensar:    { i: { h: 6, c: -10, m: 0 }, d: { h: -22, c: -150, m: 18, delante: true }, expr: 'pensando' },
    gracias:   { i: { h: 7, c: -8, m: 0 }, d: { h: 2, c: -128, m: 10, delante: true }, expr: 'sonrie', cabeza: -3 },
    celebrar:  { i: { h: 156, c: 14, m: 0, mano: 'a', osc: ['h', 6, 6] }, d: { h: 156, c: 14, m: 0, mano: 'a', osc: ['h', 6, 6.4] }, expr: 'feliz', salto: true },
    triste:    { i: { h: 3, c: -4, m: 0 }, d: { h: 3, c: -4, m: 0 }, expr: 'triste', hombros: 8 }
  };

  /* Estados del widget (los mismos nombres que IndiraTitere.ESTADOS) -> gesto y expresion del cuerpo. */
  var ESTADOS = {
    reposo: ['reposo'], serio: ['reposo'], saludo: ['saludo'], bienvenida: ['presentar'], presentarse: ['presentar'],
    pensando: ['pensar'], listo: ['explicar', 'feliz'], logro: ['celebrar'], nota: ['explicar'], gracias: ['gracias'],
    broma: ['reposo', 'guino'], duda: ['reposo', 'duda'], sorpresa: ['reposo', 'sorpresa'], error: ['triste']
  };

  var mueveReducido = global.matchMedia && global.matchMedia('(prefers-reduced-motion: reduce)');
  var contador = 0;
  var IndiraCuerpoAudio = { ctx: null };   /* un solo AudioContext por pagina */

  /* ------- Utilidades ------- */
  function acota(v, a, b) { return v < a ? a : v > b ? b : v; }
  function mezcla(a, b, t) { return a + (b - a) * t; }
  function suave(a, b, v) { var t = acota((v - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); }
  function n(v) { return Math.round(v * 100) / 100; }
  function nodo(padre, tipo, attrs) {
    var e = document.createElementNS(NS, tipo);
    if (attrs) Object.keys(attrs).forEach(function (k) { e.setAttribute(k, attrs[k]); });
    if (padre) padre.appendChild(e);
    return e;
  }
  function trazo(padre, d, fill, extra) {
    var a = { d: d, fill: fill || 'none' };
    if (extra) Object.keys(extra).forEach(function (k) { a[k] = extra[k]; });
    return nodo(padre, 'path', a);
  }
  function analizar(d) {
    var partes = d.match(/[MCLHVZ]|-?\d*\.?\d+(?:e-?\d+)?/gi), ops = [], i = 0, x = 0, y = 0, op = '';
    function lee() { return parseFloat(partes[i++]); }
    while (i < partes.length) {
      if (/^[MCLHVZ]$/i.test(partes[i])) op = partes[i++].toUpperCase();
      if (op === 'Z') { ops.push({ c: 'Z', p: [] }); continue; }
      if (op === 'C') { var p = [lee(), lee(), lee(), lee(), lee(), lee()]; x = p[4]; y = p[5]; ops.push({ c: 'C', p: p }); }
      else if (op === 'H') { x = lee(); ops.push({ c: 'L', p: [x, y] }); }
      else if (op === 'V') { y = lee(); ops.push({ c: 'L', p: [x, y] }); }
      else { x = lee(); y = lee(); ops.push({ c: op, p: [x, y] }); if (op === 'M') op = 'L'; }
    }
    return ops;
  }
  /* El pelo largo se mece: nada en la coronilla y mas cuanto mas abajo. */
  function ondear(ops, t, amp, y0, y1, fase, viento) {
    var s = '';
    for (var i = 0; i < ops.length; i++) {
      var o = ops[i], p = o.p;
      s += o.c;
      for (var j = 0; j < p.length; j += 2) {
        var k = suave(y0, y1, p[j + 1]);
        var dx = k * (amp * Math.sin(t * 1.1 + p[j + 1] * .006 + fase + (p[j] < CUELLO[0] ? 0 : .8)) + viento);
        s += (j ? ' ' : '') + n(p[j] + dx) + ' ' + n(p[j + 1] - Math.abs(dx) * .12);
      }
    }
    return s;
  }
  function trazoBoca(b) {
    var cx = BOCA_C[0], cy = BOCA_C[1];
    var xl = cx - b.w, xr = cx + b.w, yc = cy + b.c;
    return 'M' + n(xl) + ' ' + n(yc) + 'C' + n(cx - b.w * .45) + ' ' + n(cy + b.up) + ' ' + n(cx + b.w * .45) + ' ' + n(cy + b.up) + ' ' + n(xr) + ' ' + n(yc) +
      'C' + n(cx + b.w * .55) + ' ' + n(cy + b.dn) + ' ' + n(cx - b.w * .55) + ' ' + n(cy + b.dn) + ' ' + n(xl) + ' ' + n(yc) + 'Z';
  }
  function visemas(texto) {
    var cola = [], re = /([a-záéíóúüñ]*?)([aeiouáéíóúü]+)|([.,;:!?¿¡…]+)|(\s+)/gi, m;
    while ((m = re.exec(texto))) {
      if (m[3]) { cola.push({ v: 'm', ms: /[.!?…]/.test(m[3]) ? 320 : 170 }); continue; }
      if (m[4]) continue;
      var pre = (m[1] || '').toLowerCase(), voc = m[2].toLowerCase().charAt(0);
      var v = /[aá]/.test(voc) ? 'a' : /[eé]/.test(voc) ? 'e' : /[ií]/.test(voc) ? 'i' : /[oó]/.test(voc) ? 'oo' : 'u';
      if (/[mbp]$/.test(pre)) cola.push({ v: 'm', ms: 50 });
      cola.push({ v: v, ms: 125 });
    }
    return cola;
  }

  /* Resorte amortiguado: da inercia, un pequeno rebote al llegar y retraso natural entre articulaciones. */
  function Resorte(v, rigidez, amort) { this.x = v; this.v = 0; this.k = rigidez; this.d = amort; }
  Resorte.prototype.paso = function (meta, dt) {
    var a = this.k * (meta - this.x) - this.d * this.v;
    this.v += a * dt; this.x += this.v * dt;
    return this.x;
  };
  Resorte.prototype.fija = function (v) { this.x = v; this.v = 0; };

  /* ------- Construccion ------- */
  function crear(contenedor, opciones) {
    opciones = opciones || {};
    if (!T) throw new Error('IndiraCuerpo: falta indira-cuerpo-trazos.js');
    var uid = 'indira-c' + (++contador);
    var svg = nodo(null, 'svg', { viewBox: ENCUADRES[opciones.encuadre] || ENCUADRES.completo, 'class': 'indira-esqueleto', preserveAspectRatio: opciones.alinear || 'xMidYMax meet', role: 'img', 'aria-label': opciones.etiqueta || 'Indira' });
    var defs = nodo(svg, 'defs');
    function recorte(nombre, d) {
      var c = nodo(defs, 'clipPath', { id: uid + nombre });
      nodo(c, 'path', { d: d });
      return 'url(#' + uid + nombre + ')';
    }

    var gTodo = nodo(svg, 'g');           /* salto */
    var gPeso = nodo(gTodo, 'g');         /* balanceo desde los pies */

    /* Pelo de atras: gira con la cabeza, pero va detras de todo. */
    var gPeloAtras = nodo(gPeso, 'g');
    var pelo = trazo(gPeloAtras, T.pelo, '#000');
    var pelo25 = trazo(gPeloAtras, T.peloAtras25, '#000');

    /* Piernas y falda */
    var gPiernas = nodo(gPeso, 'g');
    var gPiernaI = nodo(gPiernas, 'g'), gPiernaD = nodo(gPiernas, 'g');
    trazo(gPiernaD, T.zapatoD, '#2E2E2E'); trazo(gPiernaD, T.piernaD[0], '#C8A38B'); trazo(gPiernaD, T.piernaD[1], '#8B7160');
    trazo(gPiernaI, T.zapatoI, '#2E2E2E'); trazo(gPiernaI, T.piernaI[0], '#C8A38B'); trazo(gPiernaI, T.piernaI[1], '#8B7160');
    nodo(gPiernaI, 'rect', { x: '274.799', y: '1658.29', width: '158.541', height: '79', transform: 'rotate(12.0572 274.799 1658.29)', fill: '#916B52' });
    nodo(gPiernaD, 'rect', { x: '427', y: '1688.85', width: '161.072', height: '79', transform: 'rotate(-6.09957 427 1688.85)', fill: '#916B52' });
    var falda = trazo(gPiernas, T.falda, '#2E2E2E');

    var gArriba = nodo(gPeso, 'g');       /* respiracion: todo lo que va de la cintura para arriba */
    nodo(gArriba, 'rect', { x: '386.994', y: '459.997', width: '91.7434', height: '132.413', fill: PIEL_SOMBRA });

    /* Cabeza */
    var gCabeza = nodo(gArriba, 'g');
    trazo(gCabeza, T.cara, PIEL);
    var gOrejaI = nodo(gCabeza, 'g'), gOrejaD = nodo(gCabeza, 'g');
    trazo(gOrejaD, T.orejaD, PIEL); trazo(gOrejaD, T.orejaDin, ROSA);
    trazo(gOrejaI, T.orejaI, PIEL); trazo(gOrejaI, T.orejaIin, ROSA);
    var aretaD = nodo(gOrejaD, 'ellipse', { cx: '589.5', cy: '442', rx: '12.5', ry: '12', fill: AZUL });
    var aretaI = nodo(gOrejaI, 'ellipse', { cx: '263.5', cy: '442', rx: '12.5', ry: '12', fill: AZUL });
    var gRasgos = nodo(gCabeza, 'g', { 'clip-path': recorte('-cara', T.cara) });
    var gRasgosM = nodo(gRasgos, 'g');
    var rubor = trazo(gRasgosM, T.rubor, ROSA, { opacity: '.5' });
    trazo(gRasgosM, T.nariz, LABIO);
    var bocaFondo = trazo(gRasgosM, 'M0 0', BOCA);
    var gDientes = nodo(gRasgosM, 'g', { 'clip-path': recorte('-boca', 'M0 0') });
    var clipBoca = defs.lastChild.firstChild;
    var dientes = nodo(gDientes, 'rect', { x: '380', y: '400', width: '92', height: '40', fill: '#fff' });
    var bocaLinea = trazo(gRasgosM, 'M0 0', null, { stroke: LABIO, 'stroke-width': '2', 'stroke-linejoin': 'round' });

    function ojo(lado) {
      var g = nodo(gRasgosM, 'g');
      var abierto = nodo(g, 'g');
      var blanco = lado === 'i' ? T.blancoI : T.blancoD;
      trazo(abierto, blanco, '#fff');
      var iris = nodo(nodo(abierto, 'g', { 'clip-path': recorte('-b' + lado, blanco) }), 'g');
      trazo(iris, lado === 'i' ? T.irisI : T.irisD, '#000');
      var c = lado === 'i' ? OJO_I : OJO_D;
      nodo(iris, 'circle', { cx: n(c[0] + 18), cy: n(c[1] - 14), r: '6', fill: '#fff' });
      var pest = trazo(abierto, lado === 'i' ? T.pestanaI : T.pestanaD, '#000');
      var feliz = nodo(g, 'g', { transform: 'translate(97 28)', opacity: '0' });
      if (lado === 'i') trazo(feliz, T.felizI, '#000'); else { trazo(feliz, T.felizD, '#000'); trazo(feliz, T.felizD2, '#000'); }
      return { g: g, abierto: abierto, iris: iris, pest: pest, feliz: feliz, c: c };
    }
    var oI = ojo('i'), oD = ojo('d');
    var cejaI = trazo(gRasgosM, T.cejaI, CEJA), cejaD = trazo(gRasgosM, T.cejaD, CEJA);
    var gFlequillo = nodo(gCabeza, 'g');
    trazo(gFlequillo, T.flequillo, '#000');

    /* Torso */
    var gTorso = nodo(gArriba, 'g');
    trazo(gTorso, TORSO, AZUL);
    trazo(nodo(gTorso, 'g', { 'clip-path': recorte('-torso', TORSO) }), T.sombraBlusa, AZUL_SOMBRA);

    /* Brazos */
    function brazo(lado) {
      var raiz = nodo(gArriba, 'g');
      var hombro = nodo(raiz, 'g');
      var ante = nodo(null, 'g');
      trazo(ante, ANTE, PIEL);
      trazo(ante, CODO, PIEL_SOMBRA);
      if (lado === 'i') nodo(ante, 'rect', { x: '-34', y: String(ANTEBRAZO - 36), width: '68', height: '17', rx: '8.5', fill: '#171717' });
      var mano = nodo(ante, 'g');
      var relajada = nodo(mano, 'g');
      trazo(relajada, MANO, PIEL);
      DEDOS.forEach(function (d) { trazo(relajada, d, null, { stroke: ROSA, 'stroke-width': '3', 'stroke-linecap': 'round' }); });
      var abierta = nodo(mano, 'g', { transform: 'scale(.72) rotate(196.8) translate(-160 -655)', opacity: '0' });
      trazo(abierta, T.manoAbierta, PIEL);
      T.manoLineas.forEach(function (d) { trazo(abierta, d, null, { stroke: ROSA, 'stroke-width': '2.4', 'stroke-linecap': 'round', 'stroke-linejoin': 'round' }); });
      var manga = nodo(null, 'g');
      trazo(manga, MANGA, AZUL);
      trazo(manga, PLIEGUE, null, { stroke: AZUL_SOMBRA, 'stroke-width': '5', 'stroke-linecap': 'round' });
      hombro.appendChild(ante); hombro.appendChild(manga);
      return {
        lado: lado, raiz: raiz, hombro: hombro, ante: ante, manga: manga, mano: mano, relajada: relajada, abierta: abierta,
        h: new Resorte(7, 60, 11), c: new Resorte(-8, 80, 12), m: new Resorte(0, 110, 14), ab: 0, delante: false
      };
    }
    var bI = brazo('i');
    var mechon = trazo(gArriba, T.mechon, '#000');
    var bD = brazo('d');
    var opsPelo = analizar(T.pelo), opsMechon = analizar(T.mechon);

    contenedor.appendChild(svg);

    /* ------- Estado ------- */
    function reducido() { return !!(mueveReducido && mueveReducido.matches) || !!opciones.sinMovimiento; }
    var gestoActual = 'reposo', exprManual = null, exprNombre = 'reposo';
    var boca = { w: 24, c: 0, up: 0, dn: 25, di: 1 };
    var act = { feI: 0, feD: 0, tr: 0, ceI: 0, ceD: 0, rub: .5, ojo: 1, mx: 0, my: 0, gir: 0, tx: 0, hom: 0 };
    var cab = new Resorte(0, 30, 8), cabX = new Resorte(0, 30, 8), peso = new Resorte(0, 6, 4), salto = new Resorte(0, 120, 9);
    var cursor = { x: 0, y: 0, hasta: -1 }, micro = { x: 0, y: 0, prox: 1 };
    var parpadeo = { prox: 1.5, ini: -1 }, pesoMeta = { v: 0, prox: 4 };
    var vis = null, colaBoca = [], visHasta = 0, hablando = false, promesas = [], ritmo = 0, ademan = { prox: 0, i: null, d: null };
    /* Audio real: un analizador mide el volumen en cada cuadro y de ahi sale la boca. */
    var audio = null, analizador = null, muestrasA = null, golpe = 0, audioListo = null;
    var reloj = 0, rafId = 0, ultimo = 0, destruido = false, pausado = false, saltoFase = -1;

    function exprActual() { return EXPRESIONES[exprManual || GESTOS[gestoActual].expr || 'reposo'] || EXPRESIONES.reposo; }

    function poseBrazo(b, meta, dt, s, r) {
      var g = meta;
      if (hablando && ademan[b.lado] && (gestoActual === 'reposo' || gestoActual === 'explicar')) g = ademan[b.lado];
      var osc = !r && g.osc ? g.osc : null;
      function o(k) { return osc && osc[0] === k ? Math.sin(s * osc[2]) * osc[1] : 0; }
      var h = g.h + o('h'), c = g.c + o('c'), m = (g.m || 0) + o('m');
      if (r) { b.h.fija(h); b.c.fija(c); b.m.fija(m); }
      else {
        /* Brazo suelto: se mece un poco con la respiracion y el peso. */
        var vaiven = g.h < 25 ? Math.sin(s * 1.3 + (b.lado === 'i' ? 0 : 1.7)) * 1.3 : 0;
        b.h.paso(h + vaiven, dt); b.c.paso(c + vaiven * .8, dt); b.m.paso(m, dt);
      }
      var ab = g.mano === 'a' ? 1 : 0;
      b.ab = r ? ab : mezcla(b.ab, ab, 1 - Math.exp(-dt / .07));
      var delante = !!g.delante;
      if (delante !== b.delante) {
        b.delante = delante;
        if (delante) b.hombro.appendChild(b.ante); else b.hombro.insertBefore(b.ante, b.manga);
      }
      var p = b.lado === 'i' ? HOMBRO_I : HOMBRO_D, esp = b.lado === 'i' ? '' : ' scale(-1 1)';
      b.raiz.setAttribute('transform', 'translate(' + p[0] + ' ' + n(p[1] - act.hom) + ')' + esp);
      b.hombro.setAttribute('transform', 'rotate(' + n(b.h.x) + ')');
      b.ante.setAttribute('transform', 'translate(0 ' + BRAZO + ') rotate(' + n(b.c.x) + ')');
      b.mano.setAttribute('transform', 'translate(0 ' + (ANTEBRAZO - 8) + ') rotate(' + n(b.m.x) + ') scale(1.22)');
      b.relajada.setAttribute('opacity', n(1 - b.ab));
      b.abierta.setAttribute('opacity', n(b.ab));
    }

    function pinta(dt) {
      var r = reducido(), mov = !r, s = mov ? reloj : 0;
      var g = GESTOS[gestoActual], e = exprActual();
      function hacia(k, v, tau) { act[k] = r ? v : mezcla(act[k], v, 1 - Math.exp(-dt / tau)); }

      /* Parpadeo */
      var b = 0;
      if (parpadeo.ini >= 0) {
        var d = reloj - parpadeo.ini;
        if (d < .07) b = d / .07; else if (d < .19) b = 1 - (d - .07) / .12; else parpadeo.ini = -1;
      }
      var fe = e.felices || [0, 0], ce = e.cejas || [0, 0];
      hacia('feI', fe[0], .06); hacia('feD', fe[1], .06);
      hacia('ceI', ce[0], .1); hacia('ceD', ce[1], .1);
      hacia('rub', e.rubor || .5, .25); hacia('tr', e.tristes || 0, .15); hacia('ojo', e.ojo || 1, .1);
      hacia('hom', g.hombros || 0, .3);

      /* Mirada: la expresion, el gesto, el cursor o pequenos vistazos propios */
      var vigente = reloj <= cursor.hasta;
      var mira = e.mirada || g.mira || (vigente ? [cursor.x, cursor.y] : r ? [0, 0] : [micro.x, micro.y]);
      hacia('mx', mira[0], .08); hacia('my', mira[1], .08);

      /* Boca */
      var ref = BOCAS[vis || e.boca] || BOCAS.figma, kb = r ? 1 : 1 - Math.exp(-dt / (vis ? .045 : .1));
      for (var k in ref) boca[k] = mezcla(boca[k], ref[k], kb);
      var dB = trazoBoca(boca);
      bocaFondo.setAttribute('d', dB); bocaLinea.setAttribute('d', dB); clipBoca.setAttribute('d', dB);
      dientes.setAttribute('y', n(BOCA_C[1] + boca.up - 6));
      dientes.setAttribute('height', n(Math.max(0, 6 + (boca.dn - boca.up) * .62 * boca.di)));

      /* Cabeza: gesto + habla + seguir la mirada */
      var habla = hablando && mov ? Math.sin(s * 7.7) * 1.2 + Math.sin(s * 3.1) * 1.6 : 0;
      var giroMeta = (e.giro || 0) + (g.cabeza || 0) + act.mx * 3 + habla * .6 + (mov ? Math.sin(s * .41) * .8 : 0);
      if (r) { cab.fija(giroMeta); cabX.fija(act.mx * 6); } else { cab.paso(giroMeta, dt); cabX.paso(act.mx * 6, dt); }
      var resp = mov ? Math.sin(s * 1.5) : 0;
      var asiente = hablando && mov ? Math.max(0, Math.sin(s * 4.2)) * 3 : 0;
      var trCab = 'translate(' + n(cabX.x) + ' ' + n(resp * 2 + act.my * 3 + asiente + act.hom * .5) + ') rotate(' + n(cab.x) + ' ' + CUELLO[0] + ' ' + CUELLO[1] + ')';
      gCabeza.setAttribute('transform', trCab);
      gPeloAtras.setAttribute('transform', trCab);
      /* Paralaje dentro de la cara: los rasgos se adelantan, las orejas se atrasan. */
      gRasgosM.setAttribute('transform', 'translate(' + n(act.mx * 9) + ' ' + n(act.my * 6) + ')');
      gFlequillo.setAttribute('transform', 'translate(' + n(act.mx * 4) + ' ' + n(act.my * 2.5) + ')');
      gOrejaI.setAttribute('transform', 'translate(' + n(-act.mx * 4) + ' 0)');
      gOrejaD.setAttribute('transform', 'translate(' + n(-act.mx * 4) + ' 0)');
      var cuelga = mov ? Math.sin(s * 2.1) * 2 + cab.v * .4 : 0;
      aretaI.setAttribute('transform', 'translate(' + n(cuelga) + ' 0)');
      aretaD.setAttribute('transform', 'translate(' + n(cuelga) + ' 0)');

      /* Ojos */
      [[oI, act.feI], [oD, act.feD]].forEach(function (par) {
        var o = par[0], f = par[1], cierre = Math.max(b * .95, act.tr * .18), c = o.c;
        o.abierto.setAttribute('opacity', n(1 - f));
        o.feliz.setAttribute('opacity', n(f));
        o.abierto.setAttribute('transform', 'translate(' + c[0] + ' ' + (c[1] + 30) + ') scale(' + n(act.ojo) + ' ' + n(act.ojo * (1 - cierre)) + ') translate(' + -c[0] + ' ' + -(c[1] + 30) + ')');
        o.iris.setAttribute('transform', 'translate(' + n(act.mx * 12) + ' ' + n(act.my * 7) + ')');
      });
      cejaI.setAttribute('transform', 'translate(0 ' + n(act.ceI) + ') rotate(' + n(act.tr * -10) + ' 353 285)');
      cejaD.setAttribute('transform', 'translate(0 ' + n(act.ceD) + ') rotate(' + n(act.tr * 10) + ' 494 285)');
      rubor.setAttribute('opacity', n(act.rub));

      /* Cuerpo: respiracion, peso, salto */
      gTorso.setAttribute('transform', 'translate(440 1040) scale(1 ' + n(1 + resp * .004) + ') translate(-440 -1040)');
      gArriba.setAttribute('transform', 'translate(0 ' + n(-resp * 1.5) + ')');
      var pz = r ? 0 : peso.paso(pesoMeta.v, dt);
      gPeso.setAttribute('transform', 'rotate(' + n(pz) + ' ' + PIES[0] + ' ' + PIES[1] + ')');
      gPiernaI.setAttribute('transform', 'rotate(' + n(-pz * 1.5) + ' 330 1300)');
      gPiernaD.setAttribute('transform', 'rotate(' + n(-pz * 1.5) + ' 530 1300)');
      var alto = 0;
      if (g.salto && mov) {
        var ciclo = (s * 1.25) % 1;
        alto = ciclo < .45 ? -Math.sin(ciclo / .45 * Math.PI) * 70 : 0;
      }
      gTodo.setAttribute('transform', 'translate(0 ' + n(r ? 0 : salto.paso(alto, dt)) + ')');

      /* Pelo: se mece y se queda un poco atras cuando gira la cabeza */
      if (mov) {
        var viento = -cab.v * 3 - pz * 25;
        pelo.setAttribute('d', ondear(opsPelo, s, 7, CABELLO_PIVOTE, 1180, 0, viento));
        mechon.setAttribute('d', ondear(opsMechon, s, 6, 560, 860, 1.4, viento * .6));
      }
      mechon.setAttribute('transform', trCab);

      poseBrazo(bI, g.i, dt, s, r);
      poseBrazo(bD, g.d, dt, s, r);
    }

    function programar() {
      if (reloj >= parpadeo.prox && parpadeo.ini < 0) {
        parpadeo.ini = reloj;
        parpadeo.prox = reloj + (Math.random() < .15 ? .25 : 2 + Math.random() * 4);
      }
      if (reloj >= micro.prox) {
        micro.x = (Math.random() - .5) * .9; micro.y = (Math.random() - .5) * .5;
        micro.prox = reloj + 1.5 + Math.random() * 3;
      }
      if (reloj >= pesoMeta.prox) {
        pesoMeta.v = pesoMeta.v > 0 ? -(.4 + Math.random() * .5) : (.4 + Math.random() * .5);
        pesoMeta.prox = reloj + 4 + Math.random() * 5;
      }
      /* Ademanes al hablar: manos que acompanan las frases. */
      if (hablando && reloj >= ademan.prox) {
        var op = [
          [{ h: 10, c: -62, m: -55, mano: 'a' }, null], [null, { h: 10, c: -70, m: -50, mano: 'a' }],
          [{ h: 18, c: -48, m: -65, mano: 'a' }, { h: 18, c: -48, m: -65, mano: 'a' }], [null, null],
          [{ h: 6, c: -88, m: -40 }, null]
        ][Math.floor(Math.random() * 5)];
        ademan.i = op[0]; ademan.d = op[1];
        ademan.prox = reloj + 1 + Math.random() * 1.4;
      }
      if (!hablando) { ademan.i = ademan.d = null; }
    }

    /* ------- Bucle ------- */
    function avanzaBoca() {
      var ahora = global.performance.now();
      if (ahora < visHasta) return;
      if (colaBoca.length) { var c = colaBoca.shift(); vis = c.v; visHasta = ahora + c.ms; hablando = true; }
      else {
        vis = null; hablando = false;
        global.clearInterval(ritmo); ritmo = 0;
        var p = promesas; promesas = []; p.forEach(function (f) { f(); });
      }
    }
    function cuadro(ms) {
      rafId = 0;
      if (destruido || pausado || document.hidden) return;
      var dt = ultimo ? Math.min((ms - ultimo) / 1000, .05) : .016;
      ultimo = ms; reloj += dt;
      if (audio) sigueAudio();
      programar(); pinta(dt);
      rafId = global.requestAnimationFrame(cuadro);
    }
    function sigueAudio() {
      analizador.getByteTimeDomainData(muestrasA);
      var suma = 0;
      for (var i = 0; i < muestrasA.length; i++) { var v = (muestrasA[i] - 128) / 128; suma += v * v; }
      var nivel = Math.sqrt(suma / muestrasA.length);
      /* Cada vez que la voz sube de golpe cambia la vocal: asi la boca no se queda en una sola forma. */
      if (nivel > .05 && reloj - golpe > .14) golpe = reloj;
      var ciclo = Math.floor(golpe * 7) % 3;
      vis = nivel < .015 ? 'm' : nivel < .045 ? ['e', 'i', 'u'][ciclo] : nivel < .09 ? ['e', 'oo', 'a'][ciclo] : 'a';
      hablando = !audio.paused;
    }
    function sueltaAudio() {
      if (!audio) return;
      var a = audio; audio = null; vis = null; hablando = false;
      a.onended = a.onerror = null;
      try { a.pause(); } catch (e) {}
      if (audioListo) { var f = audioListo; audioListo = null; f(); }
    }
    function arranca() { if (!rafId && !destruido && !pausado) { ultimo = 0; rafId = global.requestAnimationFrame(cuadro); } }
    function alVisibilidad() { if (!document.hidden) arranca(); }
    document.addEventListener('visibilitychange', alVisibilidad);
    function alMover(ev) {
      var rc = svg.getBoundingClientRect();
      if (!rc.width) return;
      var cx = rc.left + rc.width / 2, cy = rc.top + rc.height * (OJOS[opciones.encuadre] || OJOS.completo);
      cursor.x = acota((ev.clientX - cx) / (global.innerWidth * .5), -1, 1);
      cursor.y = acota((ev.clientY - cy) / (global.innerHeight * .5), -1, 1);
      cursor.hasta = reloj + 2.5;
    }
    if (opciones.seguirCursor !== false) global.addEventListener('pointermove', alMover, { passive: true });

    /* Para capturas: simula t segundos de golpe y se queda quieta. */
    if (opciones.congelar != null) {
      gestoActual = opciones.gesto || 'reposo';
      if (opciones.expresion) exprManual = opciones.expresion;
      for (var i = 0; i < opciones.congelar * 60; i++) { reloj += 1 / 60; pinta(1 / 60); }
      pausado = true;
    } else {
      pinta(.016);
      arranca();
    }

    return {
      gesto: function (nombre) { if (GESTOS[nombre]) { gestoActual = nombre; exprManual = null; } return this; },
      expresion: function (nombre) { exprManual = EXPRESIONES[nombre] ? nombre : null; return this; },
      estado: function (nombre) {
        var e = ESTADOS[nombre] || ESTADOS.reposo;
        gestoActual = e[0]; exprManual = e[1] || null;
        return this;
      },
      hablar: function (texto) {
        var pr = new Promise(function (ok) { promesas.push(ok); });
        colaBoca = colaBoca.concat(visemas(String(texto || '')));
        if (reducido() || !colaBoca.length) { colaBoca = []; avanzaBoca(); return pr; }
        hablando = true; ademan.prox = reloj + .3;
        if (!ritmo) ritmo = global.setInterval(avanzaBoca, 30);
        return pr;
      },
      callar: function () { sueltaAudio(); colaBoca = []; visHasta = 0; avanzaBoca(); },
      /* Reproduce un <audio> (o new Audio()) y mueve la boca con su volumen. Resuelve al terminar o al callar. */
      hablarAudio: function (el) {
        sueltaAudio();
        var Ctx = global.AudioContext || global.webkitAudioContext;
        if (!Ctx) return el.play().catch(function () {});
        var ctx = IndiraCuerpoAudio.ctx || (IndiraCuerpoAudio.ctx = new Ctx());
        if (ctx.state === 'suspended') ctx.resume();
        var fuente = ctx.createMediaElementSource(el);
        analizador = ctx.createAnalyser(); analizador.fftSize = 1024;
        muestrasA = new Uint8Array(analizador.fftSize);
        fuente.connect(analizador); analizador.connect(ctx.destination);
        colaBoca = []; visHasta = 0; if (ritmo) avanzaBoca();
        audio = el;
        if (!reducido()) ademan.prox = reloj + .3;
        var pr = new Promise(function (ok) { audioListo = ok; });
        el.onended = el.onerror = function () { if (audio === el) sueltaAudio(); };
        el.play().catch(function () { if (audio === el) sueltaAudio(); });
        return pr;
      },
      mirar: function (x, y) { cursor.x = acota(x, -1, 1); cursor.y = acota(y, -1, 1); cursor.hasta = reloj + 3; },
      pausar: function () { pausado = true; },
      reanudar: function () { pausado = false; arranca(); },
      destruir: function () {
        sueltaAudio();
        destruido = true;
        if (rafId) global.cancelAnimationFrame(rafId);
        if (ritmo) global.clearInterval(ritmo);
        document.removeEventListener('visibilitychange', alVisibilidad);
        global.removeEventListener('pointermove', alMover);
        if (svg.parentNode) svg.parentNode.removeChild(svg);
      },
      elemento: svg
    };
  }

  global.IndiraCuerpo = { crear: crear, GESTOS: Object.keys(GESTOS), EXPRESIONES: Object.keys(EXPRESIONES), ESTADOS: Object.keys(ESTADOS) };
})(window);
