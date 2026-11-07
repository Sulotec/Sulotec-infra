/*
 * Titere 2.5D de Indira. SVG generado aqui mismo a partir de las capas de Figma
 * (indira-rostro.svg e indira-guino.svg). Sin dependencias, sin inline ni eval: cumple script-src 'self'.
 *
 *   var t = IndiraTitere.crear(contenedor, { encuadre: 'busto' | 'medio' | 'cara' });
 *   t.expresion('feliz');  t.hablar('Hola');  t.callar();  t.mirar(0.5, -0.2);  t.voz(true);
 *
 * Los estilos van en indira-titere.css; dentro de un Shadow DOM hay que enlazarlo en esa raiz.
 */
(function (global) {
  'use strict';

  var SVG_NS = 'http://www.w3.org/2000/svg';
  var PIEL = '#F2D2BD', ROSA = '#DEA3A7', LABIO = '#B57880', AZUL = '#A4C6FF', CEJA = '#251608';

  /* Mapa unico de estados: cambiar una pose es cambiar solo el nombre de archivo aqui.
   * Las de poses/ son las fotos vectorizadas (se ven nitidas a cualquier tamano). */
  var POSES = {
    saludo: 'poses/saludo.svg', pensando: 'poses/pensando.svg', pulgar: 'poses/pulgar.svg', victoria: 'poses/victoria.svg',
    libreta: 'poses/libreta.svg', feliz: 'poses/feliz.svg', picara: 'poses/picara.svg', preocupada: 'poses/preocupada.svg',
    llorando: 'poses/llorando.svg', sentada: 'poses/sentada.svg',
    brazosCruzados: 'poses/brazos-cruzados.svg', manoPecho: 'poses/mano-pecho.svg', manosJuntas: 'poses/manos-juntas.svg', triste: 'poses/triste.svg',
    /* Vectores de Figma INdira (bG0jtkDXsV8zYIrzkE6g6T): 9:240, 9:182 y 1:48. */
    saludoFeliz: 'saludo-feliz.svg', contenta: 'ojos-abiertos.svg', cuerpo: 'cuerpo-completo.svg'
  };
  /* Movimiento de cada pose mientras esta a la vista (reglas en indira-titere.css). */
  var MOVIMIENTO = {
    saludo: 'saluda', saludoFeliz: 'saluda',
    victoria: 'salta', pulgar: 'rebota', feliz: 'rebota', picara: 'rebota', contenta: 'rebota', manosJuntas: 'rebota',
    pensando: 'piensa', libreta: 'piensa', brazosCruzados: 'piensa', sentada: 'piensa',
    triste: 'decae', llorando: 'decae', preocupada: 'decae',
    manoPecho: 'respira', cuerpo: 'respira'
  };
  var ESTADOS = {
    reposo: { expresion: 'reposo' },
    saludo: { expresion: 'feliz', pose: 'saludoFeliz' },
    bienvenida: { expresion: 'feliz', pose: 'contenta' },
    presentarse: { expresion: 'reposo', pose: 'cuerpo' },
    pensando: { expresion: 'pensando' },
    listo: { expresion: 'feliz', pose: 'pulgar' },
    logro: { expresion: 'feliz', pose: 'victoria' },
    nota: { expresion: 'reposo', pose: 'libreta' },
    gracias: { expresion: 'feliz', pose: 'manoPecho' },
    broma: { expresion: 'guino' },
    duda: { expresion: 'duda' },
    sorpresa: { expresion: 'sorpresa' },
    error: { expresion: 'triste' },       /* Solo para un fallo real del servicio. */
    serio: { expresion: 'reposo' }        /* Cumplimiento y errores de cobro: neutra. */
  };

  /* ------- Capas de Figma, con su trazo original ------- */
  var D = {
    /* Vector 25 y 24: solo cambia lo que queda bajo el corte, para que el vaiven no descubra el borde. */
    pelo25: 'M216.5 119.5C258.5 73.9 324 70.1667 351.5 74L393 98.5L476 204.5V397L469 720L-5 720C-15.5 677.333 -32.8 668.1 -18 620.5C0.500004 561 87 570.5 109 533C131 495.5 38 465.5 27.5 411C17 356.5 80 322.5 123 310.5C166 298.5 164 176.5 216.5 119.5Z',
    pelo24: 'M325 181.5C337.8 158.3 325 145.833 317 142.5C301 110.5 312 107.5 325 85C338 62.5 416.5 43 487.5 102.5C558.5 162 548.5 208 548.5 253.5C548.5 299 564 308.5 622 382.5C698.424 480.007 461.5 545.5 661 655.5L711 683V730H446.5V666C444.667 656.333 438.3 627.9 427.5 591.5C414 546 429 482.5 446.5 446.5C464 410.5 456.5 354.5 416.5 313C390.265 285.781 392.708 240.348 399.583 210.533C396.738 216.971 392.518 223.759 386.5 229C371 242.5 352.5 238.5 345 258.5C339 274.5 347.5 292.833 352.5 300C336.667 292.5 302.6 269.7 293 238.5C281 199.5 309 210.5 325 181.5Z',
    flequillo26: 'M246 59.5C290.8 35.5 333.667 59.1667 349.5 74L344 179.5C328.5 184.333 292.9 196.5 274.5 206.5C256.1 216.5 256.167 245 258.5 258C251 253.833 234 241.5 226 225.5C218.088 209.676 225.5 181.135 230.34 168.418C226.631 170.162 219.265 173.531 206 179.5C174 193.9 173.333 237.833 177 258C162.833 245.167 132.7 211.5 125.5 179.5C116.5 139.5 190 89.5 246 59.5Z',
    cara18: 'M334.559 84.3081C229.559 77.3081 183 185.5 183 217.808C183 255.975 176.016 319.952 170.5 354.5C161 414 268.059 496.808 311.059 494.308C354.059 491.808 377.559 479.808 442.059 436.808C506.559 393.808 513.559 282.308 515.559 217.808C517.559 153.308 439.559 91.3081 334.559 84.3081Z',
    rubor31: 'M280.5 370C237.51 354.232 200.902 310.444 178.535 312.792L175.772 339.147C171.902 347.288 168.123 369.918 183.962 395.307C203.761 427.044 222.792 385.422 276 391C329.208 396.578 425.883 442.285 431.649 401.665C437.415 361.044 334.238 389.71 280.5 370Z',
    sombra30: 'M216 186L182 211L191.5 176L216 137H288.5C332.333 145.833 420.6 163.9 423 165.5C426 167.5 438.5 226.5 438 240C437.6 250.8 460.167 314.5 471.5 345L457 439C450.167 411 438.5 348.5 422.5 331.5C405.39 313.321 404 313.5 393.5 292.5C385.1 275.7 386.5 254 387 240C378 243.5 355.6 245.5 352 263.5C347.5 286 361.5 308.5 361.5 308.5C361.5 308.5 312.25 302 287.5 243.5C282 230.5 289.5 211 275.5 219.5C264.3 226.3 264.167 253.667 265.5 266.5C261.167 266.833 248.5 263.4 232.5 247C216.5 230.6 214.833 199.5 216 186Z',
    nariz22: 'M274.5 370H271.5L266.5 392.5L271.5 405L274.5 370Z',
    oreja21: 'M540.428 332.026C529.015 307.016 500.799 334.631 488.117 351.565L469.528 395.418C468.375 404.826 466.761 427.896 469.528 444.916C472.986 466.191 503.249 444.916 527.459 433.627C551.669 422.338 554.695 363.288 540.428 332.026Z',
    oreja29: 'M505.3 358.101C512.78 349.298 532.217 356.691 541 361.487C541 364.873 540.49 372.491 538.45 375.877C536.41 379.263 529.1 371.645 525.7 367.412C527.117 372.773 529.95 387.728 529.95 404.657C529.95 421.586 513.517 422.997 505.3 421.586C507.567 417.918 511.93 409.397 511.25 404.657C510.57 399.917 496.8 396.475 490 395.346C491.983 386.599 497.82 366.905 505.3 358.101Z',
    ceja27: 'M254.5 235C239.941 224.723 212.833 229.833 200 235C208.667 235 217.69 232.698 231.5 235C246.5 237.5 265 249.667 267 257C268.167 254.833 263 241 254.5 235Z',
    ceja28: 'M378.733 263.102C396.016 258.754 419.467 273.278 429.581 282.718C421.495 279.598 413.904 274.203 400.192 271.38C385.297 268.314 363.658 273.006 359.153 279.129C358.844 276.687 368.643 265.64 378.733 263.102Z',
    blusa32: 'M436.5 526.5C430.886 505.65 417.5 557.5 412 561L336.5 553.5C328.5 559.833 309.1 573.7 295.5 578.5C278.5 584.5 218 580 180.5 589.5C150.5 597.1 149.333 650.667 152.5 676.5L600 682.5C604.5 673.667 613.4 650.7 613 629.5C612.5 603 576 594.5 540.5 587.5C505 580.5 450.5 578.5 436.5 526.5Z',
    /* Ojo izquierdo: Vector 33 (blanco) y Vector 34 (iris y pestana, aqui separados). */
    blancoI: 'M184 328.5C180 312.5 176.5 304 186 283L190.5 276L212 273L240 283L260 340C256 344.333 245.7 353.7 236.5 356.5C225 360 209.5 356 202 352.5C192 347.833 186.062 336.746 184 328.5Z',
    silueta34: 'M181.391 280.61C187.443 272.981 203.08 262.178 225.033 271.435C248.308 281.25 261.552 305.028 265.265 315.691C265.152 320.266 264.847 331.239 264.535 338.532C264.146 347.648 255.359 362.658 238.029 360.024C220.7 357.391 220.004 358.266 214.347 336.633C209.821 319.327 214.164 289.046 216.901 276.069C214.391 275.5 211.882 275.221 209.4 275.292C191.508 275.799 183.891 278.541 181.391 280.61Z',
    irisI: 'M216.901 276.069L225.033 271.435C248.308 281.25 261.552 305.028 265.265 315.691C265.152 320.266 264.847 331.239 264.535 338.532C264.146 347.648 255.359 362.658 238.029 360.024C220.7 357.391 220.004 358.266 214.347 336.633C209.821 319.327 214.164 289.046 216.901 276.069Z',
    pestanaI: 'M181.391 280.61C187.443 272.981 203.08 262.178 225.033 271.435C237 276.5 247 285.5 254 295C244 286.5 230 279 216.901 276.069C214.391 275.5 211.882 275.221 209.4 275.292C191.508 275.799 183.891 278.541 181.391 280.61Z',
    /* Ojo derecho: Vector 37 (blanco), 36 (iris) y 35 (pestana). */
    blancoD: 'M335 348.5C329.5 328.5 333.833 319.667 338 310L360.5 298.5L380.5 295.5L405.5 304C414.667 310.167 433.5 323.7 435.5 328.5C438 334.5 442.5 348.5 438.5 369C436.853 377.443 424 384.74 409.5 383C384.5 380 368.5 378 357.5 375.5C346.5 373 340.28 367.7 335 348.5Z',
    irisD: 'M368.473 353.259C364.897 334.753 370.598 305.98 373.5 296.5L391 299C402.373 302.729 426.095 313.223 431 326.5C437.131 343.096 426.193 376.661 421.941 380.666C417.689 384.671 389.876 381.394 383.501 380.295C377.127 379.196 372.943 376.391 368.473 353.259Z',
    pestanaD: 'M406.859 301.041C375.541 287.813 345.904 303.718 335 313.324C343.401 307.497 365.459 296.884 386.481 301.041C407.502 305.198 430.99 326.079 440.107 336C448.508 335.528 462.308 333.543 450.296 329.386C435.28 324.189 446.006 317.576 406.859 301.041Z',
    /* Vector 20: el ojo cerrado que ya trae el guino de Figma. El izquierdo es este mismo, reflejado. */
    cerradoD: 'M349.14 365L341.5 353C349.14 351.5 345.54 347.222 331.14 347.222C313.14 347.222 377.14 342.222 406.14 347.222C429.34 351.222 441.14 377.556 444.14 390.222C437.306 384.389 420.14 371.022 406.14 364.222C392.14 357.422 358.973 362.167 349.14 365Z',
    /*
     * Parpados: lo que se ve del ojo es lo que queda debajo de este contorno, que baja al cerrar.
     * No se pinta piel encima: asi detras aparece la cara, o el mechon de pelo donde lo hay.
     */
    parpadoI: 'M120 300L181.391 280.61C187.443 272.981 203.08 262.178 225.033 271.435C248.308 281.25 261.552 305.028 265.265 315.691L300 325V520H120Z',
    parpadoD: 'M300 330L335 313.324C343.401 307.497 365.459 296.884 386.481 301.041C407.502 305.198 430.99 326.079 440.107 336L480 350V520H300Z',
    /* Relleno bajo la cara: evita que asome el fondo entre el flequillo y el pelo de atras al girar. */
    relleno: 'M166 185L230 150V260L190 330L172 320L160 275Z',
    lagrima: 'M0 -13C4.5 -5 8 -1 8 4.5C8 9.5 4.4 13 0 13C-4.4 13 -8 9.5 -8 4.5C-8 -1 -4.5 -5 0 -13Z',
    brillo: 'M372 84C424 78 488 112 516 166C528 190 534 214 534 236C524 190 498 146 462 118C434 96 402 86 372 84Z'
  };

  /*
   * Bocas: tres curvas cubicas que empiezan en p0 y vuelven a p0, siempre con la misma estructura
   * para poder interpolarlas. dientes = que tanto de la boca es blanco (1 = todo, como en Figma).
   */
  var BOCAS = {
    reposo:   { p: [311.776, 420.227, 308.898, 418.561, 283.393, 426.473, 271, 430.637, 279.395, 437.404, 297.625, 450.521, 303.381, 448.855, 310.577, 446.773, 315.374, 422.309], dientes: 1 },
    /* Vector 23 de Figma, cerrada. */
    sonrisa:  { p: [302, 426.5, 296.5, 431, 281, 431, 270.5, 424.5, 274.833, 426.5, 284.9, 430.4, 290.5, 430, 296.1, 429.6, 300.5, 427.5], dientes: 0 },
    feliz:    { p: [319, 414, 306, 413, 276, 422, 262, 429, 272, 442, 293, 459, 305, 457, 317, 454.5, 323, 420], dientes: .72 },
    o:        { p: [300, 424, 291, 420.5, 280.5, 426.5, 279.5, 435, 278.5, 445, 286, 455.5, 295, 454, 304, 452.5, 309, 429], dientes: 0 },
    duda:     { p: [306, 423, 299, 427, 285, 434, 276, 434, 284, 435, 293, 433, 298, 431, 302, 429.5, 305, 426], dientes: 0 },
    pensando: { p: [304, 429, 297, 433, 286, 435, 279, 433.5, 285, 436.5, 293, 436.5, 297, 435, 300, 434, 303, 431.5], dientes: 0 },
    triste:   { p: [307, 438, 301, 430, 281, 429, 274, 439, 281, 431.5, 288, 430.5, 292, 430.5, 297, 430.5, 303, 433], dientes: 0 },
    /* Vocales para hablar. */
    a:        { p: [314, 418, 303, 417, 279, 425, 268, 431, 274, 444, 292, 462, 303, 460, 314, 458, 319, 423], dientes: .42 },
    e:        { p: [315, 420, 303, 419, 279, 426, 267, 431.5, 276, 440, 295, 450, 304, 448.5, 312, 447, 319, 425], dientes: .62 },
    i:        { p: [314, 422, 303, 422, 280, 428, 269, 431, 279, 436, 295, 441, 303, 440, 310, 439, 316, 427], dientes: .9 },
    u:        { p: [301, 426, 294, 423.5, 284, 428, 283, 434.5, 282.5, 441, 288, 448, 294.5, 447, 301, 446, 306, 430], dientes: 0 },
    m:        { p: [302, 428, 296.5, 431, 281, 431.5, 272, 427, 278, 430, 285, 431, 290.5, 431, 296, 431, 300.5, 429.5], dientes: 0 }
  };
  BOCAS.oo = BOCAS.o;

  /*
   * Expresiones. cejas: [subida, giro] de cada una. mirada: ojos a un lado fijos (si no, siguen al cursor).
   * Nada de enojada ni lengua aqui: decision del dueno.
   */
  var EXPRESIONES = {
    reposo:   { boca: 'reposo' },
    feliz:    { boca: 'sonrisa', parpado: [.14, .14], cejaI: [-7, -1], cejaD: [-7, 1], giro: -1.2, rubor: .72, alto: -2 },
    guino:    { boca: 'sonrisa', parpado: [0, 1], arco: [0, 1], cejaI: [-6, -2], cejaD: [2, 0], giro: 2.4, rubor: .62 },
    sorpresa: { boca: 'o', cejaI: [-15, 0], cejaD: [-15, 0], ojo: 1.09, iris: .9, alto: -5 },
    duda:     { boca: 'duda', parpado: [.05, .12], cejaI: [-14, -5], cejaD: [5, 5], mirada: [.7, -.6], giro: -3 },
    pensando: { boca: 'pensando', parpado: [.06, .06], cejaI: [-5, -2], cejaD: [-9, -2], mirada: [1, -.7], giro: 2.6, alto: -1 },
    triste:   { boca: 'triste', parpado: [.22, .22], cejaI: [-3, -10], cejaD: [-3, 10], mirada: [-.1, .8], giro: -2.2, alto: 3, rubor: .62, lagrima: 1 }
  };
  var CENTRO_CEJA_I = [233, 241], CENTRO_CEJA_D = [394, 270], CENTRO_OJO_I = [222, 316], CENTRO_OJO_D = [388, 340];
  var PIVOTE_CABEZA = [335, 480];
  var CAIDA_I = 92, CAIDA_D = 84;
  var ENCUADRES = { busto: '-45 30 745 618', medio: '60 30 570 618', cara: '118 44 468 468' };

  var mueveReducido = global.matchMedia && global.matchMedia('(prefers-reduced-motion: reduce)');
  var contador = 0;

  /* ------- Utilidades ------- */
  function acota(v, a, b) { return v < a ? a : v > b ? b : v; }
  function mezcla(a, b, t) { return a + (b - a) * t; }
  function suave(a, b, v) { var t = acota((v - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); }
  function n1(v) { return Math.round(v * 100) / 100; }

  function nodo(padre, tipo, attrs) {
    var e = document.createElementNS(SVG_NS, tipo);
    if (attrs) Object.keys(attrs).forEach(function (k) { e.setAttribute(k, attrs[k]); });
    if (padre) padre.appendChild(e);
    return e;
  }
  function trazo(padre, d, fill, extra) {
    var a = { d: d };
    if (fill) a.fill = fill;
    if (extra) Object.keys(extra).forEach(function (k) { a[k] = extra[k]; });
    return nodo(padre, 'path', a);
  }

  /* Convierte un trazo (M, C, L, H, V, Z absolutos, como exporta Figma) en puntos para deformarlo. */
  function analizar(d) {
    var partes = d.match(/[MCLHVZ]|-?\d*\.?\d+/g), ops = [], i = 0, x = 0, y = 0, op = '';
    function lee() { return parseFloat(partes[i++]); }
    while (i < partes.length) {
      if (/[MCLHVZ]/.test(partes[i])) op = partes[i++];
      if (op === 'Z') { ops.push({ c: 'Z', p: [] }); continue; }
      if (op === 'C') { var p = [lee(), lee(), lee(), lee(), lee(), lee()]; x = p[4]; y = p[5]; ops.push({ c: 'C', p: p }); }
      else if (op === 'H') { x = lee(); ops.push({ c: 'L', p: [x, y] }); }
      else if (op === 'V') { y = lee(); ops.push({ c: 'L', p: [x, y] }); }
      else { x = lee(); y = lee(); ops.push({ c: op, p: [x, y] }); if (op === 'M') op = 'L'; }
    }
    return ops;
  }
  /* Vaiven: solo se mueve lo que esta debajo de la cabeza, y mas cuanto mas abajo. */
  function ondear(ops, t, amp, y0, y1, fase) {
    var s = '';
    for (var i = 0; i < ops.length; i++) {
      var o = ops[i], p = o.p;
      s += o.c;
      for (var j = 0; j < p.length; j += 2) {
        var k = suave(y0, y1, p[j + 1]);
        var dx = amp * k * Math.sin(t * 1.05 + p[j + 1] * .009 + fase);
        s += (j ? ' ' : '') + n1(p[j] + dx) + ' ' + n1(p[j + 1] + dx * .16);
      }
    }
    return s;
  }
  function trazoBoca(a) {
    return 'M' + n1(a[0]) + ' ' + n1(a[1]) + 'C' + n1(a[2]) + ' ' + n1(a[3]) + ' ' + n1(a[4]) + ' ' + n1(a[5]) + ' ' + n1(a[6]) + ' ' + n1(a[7]) +
      'C' + n1(a[8]) + ' ' + n1(a[9]) + ' ' + n1(a[10]) + ' ' + n1(a[11]) + ' ' + n1(a[12]) + ' ' + n1(a[13]) +
      'C' + n1(a[14]) + ' ' + n1(a[15]) + ' ' + n1(a[16]) + ' ' + n1(a[17]) + ' ' + n1(a[0]) + ' ' + n1(a[1]) + 'Z';
  }
  /* Los dientes son la parte alta de la boca: acerca el borde inferior al segmento p0-p1. */
  function trazoDientes(a, f) {
    var mx = (a[0] + a[6]) / 2, my = (a[1] + a[7]) / 2, b = a.slice();
    for (var i = 8; i < 18; i += 2) {
      if (i === 8 || i >= 10) { b[i] = mx + (a[i] - mx) * f; b[i + 1] = my + (a[i + 1] - my) * f; }
    }
    return trazoBoca(b);
  }

  /* Silabas aproximadas en espanol: cada grupo de vocales es un golpe de boca. */
  function visemas(texto) {
    var cola = [], re = /([a-záéíóúüñ]*?)([aeiouáéíóúü]+)|([.,;:!?¿¡…]+)|(\s+)/gi, m;
    while ((m = re.exec(texto))) {
      if (m[3]) { cola.push({ v: 'm', ms: /[.!?…]/.test(m[3]) ? 300 : 170 }); continue; }
      if (m[4]) continue;
      var pre = (m[1] || '').toLowerCase(), voc = m[2].toLowerCase().charAt(0);
      var v = /[aá]/.test(voc) ? 'a' : /[eé]/.test(voc) ? 'e' : /[ií]/.test(voc) ? 'i' : /[oó]/.test(voc) ? 'oo' : 'u';
      if (/[mbp]$/.test(pre)) cola.push({ v: 'm', ms: 45 });
      cola.push({ v: v, ms: 130 });
    }
    return cola;
  }

  /* ------- Voz del navegador (opcional, apagada por defecto) ------- */
  var CLAVE_VOZ = 'indira.voz';
  function hayVoz() { return !!(global.speechSynthesis && global.SpeechSynthesisUtterance); }
  function eligeVoz() {
    if (!hayVoz()) return null;
    var voces = global.speechSynthesis.getVoices() || [], es = voces.filter(function (v) { return /^es([-_]|$)/i.test(v.lang); });
    if (!es.length) return null;
    var orden = [/es[-_]PE/i, /es[-_]419/i, /es[-_](MX|CO|AR|CL|US)/i, /es/i], fem = /sabina|paulina|helena|laura|elena|dalia|m[oó]nica|paloma|camila|salom[eé]|female|mujer/i;
    for (var i = 0; i < orden.length; i++) {
      var grupo = es.filter(function (v) { return orden[i].test(v.lang); });
      if (grupo.length) return grupo.filter(function (v) { return fem.test(v.name); })[0] || grupo[0];
    }
    return es[0];
  }

  /* ------- El titere ------- */
  function crear(contenedor, opciones) {
    opciones = opciones || {};
    var fijo = opciones.fijo || null;   /* Pose congelada, para hojas de prueba: {x, y, boca, parpado}. */
    var uid = 'indira-t' + (++contador);
    var encuadre = ENCUADRES[opciones.encuadre] || ENCUADRES.busto;

    var svg = nodo(null, 'svg', { viewBox: encuadre, 'class': 'indira-titere', fill: 'none', preserveAspectRatio: opciones.alinear || 'xMidYMax meet', role: 'img', 'aria-label': opciones.etiqueta || 'Indira' });
    var defs = nodo(svg, 'defs');
    function recorte(nombre, trazos) {
      var c = nodo(defs, 'clipPath', { id: uid + nombre });
      trazos.forEach(function (d) { nodo(c, 'path', { d: d }); });
      return 'url(#' + uid + nombre + ')';
    }
    var clipCara = recorte('-cara', [D.cara18]);
    var clipOjoI = recorte('-oi', [D.blancoI, D.silueta34]);
    var clipOjoD = recorte('-od', [D.blancoD, D.irisD]);
    var clipParpI = recorte('-pi', [D.parpadoI]), parpI = defs.lastChild.firstChild;
    var clipParpD = recorte('-pd', [D.parpadoD]), parpD = defs.lastChild.firstChild;
    var clipPelo = recorte('-p24', [D.pelo24]);
    var c9 = nodo(defs, 'clipPath', { id: uid + '-cuello' });
    nodo(c9, 'rect', { x: '310.577', y: '464.089', width: '97', height: '140', transform: 'rotate(-16.0076 310.577 464.089)' });

    /* De atras hacia adelante, en el mismo orden de Figma. */
    var gResp = nodo(svg, 'g');
    var gAtras = nodo(gResp, 'g');
    var p25 = trazo(gAtras, D.pelo25, '#000');
    var gCuello = nodo(gResp, 'g');
    nodo(gCuello, 'rect', { x: '310.577', y: '464.089', width: '97', height: '140', transform: 'rotate(-16.0076 310.577 464.089)', fill: PIEL });
    /* Sombra del menton sobre el cuello: da volumen y se mueve con la cabeza. */
    var gSombra = nodo(nodo(gCuello, 'g', { 'clip-path': 'url(#' + uid + '-cuello)' }), 'g');
    trazo(gSombra, D.cara18, ROSA, { opacity: '.6' });

    var gCabeza = nodo(gResp, 'g');
    trazo(gCabeza, D.relleno, '#000');
    trazo(gCabeza, D.cara18, PIEL);
    var gRecorteA = nodo(gCabeza, 'g', { 'clip-path': clipCara });
    var gRasgosA = nodo(gRecorteA, 'g');
    var rubor = trazo(gRasgosA, D.rubor31, ROSA, { opacity: '.5' });
    var gSombraPelo = nodo(gRecorteA, 'g');
    trazo(gSombraPelo, D.sombra30, ROSA);
    var gRasgosB = nodo(gRecorteA, 'g');

    /* Ojo izquierdo */
    var gOjoI = nodo(gRasgosB, 'g');
    var abiertoI = nodo(gOjoI, 'g');
    var bajoI = nodo(abiertoI, 'g', { 'clip-path': clipParpI });
    trazo(bajoI, D.silueta34, '#fff');
    trazo(bajoI, D.blancoI, '#fff', { stroke: '#fff' });
    var irisI = nodo(nodo(bajoI, 'g', { 'clip-path': clipOjoI }), 'g');
    trazo(irisI, D.irisI, '#000');
    nodo(irisI, 'circle', { cx: '243', cy: '307', r: '6.5', fill: '#fff' });
    var pestI = trazo(abiertoI, D.pestanaI, '#000');
    var arcoI = trazo(gOjoI, D.cerradoD, '#000', { opacity: '0', transform: 'matrix(-.708 0 0 .85 496.3 23.05)' });

    trazo(gRasgosB, D.nariz22, LABIO);
    var bocaFondo = trazo(gRasgosB, 'M0 0', LABIO);
    var bocaDientes = trazo(gRasgosB, 'M0 0', '#fff');
    var bocaLinea = trazo(gRasgosB, 'M0 0', null, { stroke: LABIO, 'stroke-linejoin': 'round' });
    var gLagrima = nodo(gRasgosB, 'g', { opacity: '0' });
    trazo(gLagrima, D.lagrima, AZUL, { stroke: '#fff', 'stroke-width': '1.5' });
    nodo(gLagrima, 'circle', { cx: '-2.6', cy: '4', r: '2', fill: '#fff' });

    /* Pelo y oreja. El orden de Figma deja la oreja sobre el pelo. */
    var gPelo = nodo(gCabeza, 'g');
    var p24 = trazo(gPelo, D.pelo24, '#000');
    var gBrillo = nodo(nodo(gPelo, 'g', { 'clip-path': clipPelo }), 'g');
    trazo(gBrillo, D.brillo, AZUL, { opacity: '.13' });
    var gOreja = nodo(gCabeza, 'g');
    trazo(gOreja, D.oreja21, PIEL);
    trazo(gOreja, D.oreja29, ROSA);
    var aretaD = nodo(gOreja, 'circle', { cx: '501', cy: '453', r: '13', fill: AZUL });
    var gFlequillo = nodo(gCabeza, 'g');
    trazo(gFlequillo, D.flequillo26, '#000');
    var aretaI = nodo(gCabeza, 'circle', { cx: '177', cy: '437', r: '13', fill: AZUL });

    /* Cejas y ojo derecho van sobre el pelo, como en Figma. */
    var gRasgosC = nodo(nodo(gCabeza, 'g', { 'clip-path': clipCara }), 'g');
    var cejaI = trazo(gRasgosC, D.ceja27, CEJA);
    var cejaD = trazo(gRasgosC, D.ceja28, CEJA);
    var gOjoD = nodo(gRasgosC, 'g');
    var abiertoD = nodo(gOjoD, 'g');
    var bajoD = nodo(abiertoD, 'g', { 'clip-path': clipParpD });
    trazo(bajoD, D.blancoD, '#fff');
    var irisD = nodo(nodo(bajoD, 'g', { 'clip-path': clipOjoD }), 'g');
    trazo(irisD, D.irisD, '#000');
    nodo(irisD, 'circle', { cx: '405', cy: '330', r: '7.5', fill: '#fff' });
    var pestD = trazo(abiertoD, D.pestanaD, '#000');
    var arcoD = trazo(gOjoD, D.cerradoD, '#000', { opacity: '0' });

    var gCuerpo = nodo(gResp, 'g');
    nodo(gCuerpo, 'rect', { x: '311', y: '517.749', width: '118.357', height: '140', rx: '10', transform: 'rotate(-16.0076 311 517.749)', fill: AZUL });
    trazo(gCuerpo, D.blusa32, AZUL, { stroke: AZUL });

    var ops25 = analizar(D.pelo25), ops24 = analizar(D.pelo24);

    /* ------- Estado ------- */
    function reducido() { return !!(mueveReducido && mueveReducido.matches) || !!opciones.sinMovimiento; }
    var nombreExpr = 'reposo';
    var boca = BOCAS.reposo.p.slice();
    /* act = valor pintado; todos se acercan a su objetivo con la misma suavidad. */
    var act = { pI: 0, pD: 0, aI: 0, aD: 0, ojo: 1, iris: 1, gI: 0, rub: .5, alto: 0, lag: 0, dientes: 1,
      ciY: 0, ciR: 0, cdY: 0, cdR: 0, mx: 0, my: 0, px: 0, py: 0 };
    var cursor = { x: 0, y: 0, hasta: -1 };   /* Hacia donde mira por el cursor o por mirar(). */
    var micro = { x: 0, y: 0, prox: 0 };
    var parpadeo = { prox: 1 + Math.random() * 2, ini: -1, doble: false };
    var vis = null, colaBoca = [], visHasta = 0;
    var promesas = [];
    var rafId = 0, ritmoId = 0, pausado = false, ultimo = 0, reloj = 0, destruido = false, hablando = false;

    /* Voz */
    var vozActiva = false;
    try { vozActiva = opciones.voz === true || (opciones.voz !== false && !!global.localStorage && localStorage.getItem(CLAVE_VOZ) === '1'); } catch (e) {}
    if (!hayVoz()) vozActiva = false;
    var bufVoz = '', temporizadorVoz = 0, enVoz = 0, turnoVoz = 0, vivas = [];

    function objetivo() {
      var e = EXPRESIONES[nombreExpr];
      /* Parpadeo: baja en 70 ms y sube en 110 ms. */
      var b = 0;
      if (parpadeo.ini >= 0) {
        var d = reloj - parpadeo.ini;
        if (d < .07) b = d / .07;
        else if (d < .18) b = 1 - (d - .07) / .11;
        else {
          parpadeo.ini = -1;
          if (parpadeo.doble) { parpadeo.doble = false; parpadeo.prox = reloj + .12; }
        }
      }
      var pp = e.parpado || [0, 0], ar = e.arco || [0, 0];
      if (fijo && fijo.parpado != null) { pp = [fijo.parpado, fijo.parpado]; b = 0; }
      return {
        pI: ar[0] ? 1 : Math.max(pp[0], b * .96), pD: ar[1] ? 1 : Math.max(pp[1], b * .96),
        aI: ar[0], aD: ar[1],
        ojo: e.ojo || 1, iris: e.iris || 1, gir: e.giro || 0, rub: e.rubor || .5, alto: e.alto || 0, lag: e.lagrima || 0,
        ciY: (e.cejaI || [0, 0])[0], ciR: (e.cejaI || [0, 0])[1], cdY: (e.cejaD || [0, 0])[0], cdR: (e.cejaD || [0, 0])[1],
        mirada: e.mirada
      };
    }

    function pinta(dt, instantaneo) {
      var t = objetivo(), r = reducido() || instantaneo;
      function hacia(k, v, tau) { act[k] = r ? v : mezcla(act[k], v, 1 - Math.exp(-dt / tau)); }
      var mov = !reducido() && !fijo;

      /* Paralaje y mirada: el cursor o mirar(); si nadie mueve nada, pequenos movimientos propios. */
      var vigente = reloj <= cursor.hasta;
      var parX = fijo ? (fijo.x || 0) : reducido() ? 0 : vigente ? cursor.x : micro.x;
      var parY = fijo ? (fijo.y || 0) : reducido() ? 0 : vigente ? cursor.y : micro.y;
      hacia('px', parX, .22); hacia('py', parY, .22);
      var libreX = reducido() && vigente ? cursor.x : parX, libreY = reducido() && vigente ? cursor.y : parY;
      hacia('mx', t.mirada ? t.mirada[0] : libreX, .09);
      hacia('my', t.mirada ? t.mirada[1] : libreY, .09);

      hacia('pI', t.pI, t.pI > act.pI ? .03 : .06); hacia('pD', t.pD, t.pD > act.pD ? .03 : .06);
      hacia('aI', t.aI && act.pI > .8 ? 1 : 0, .05); hacia('aD', t.aD && act.pD > .8 ? 1 : 0, .05);
      hacia('ojo', t.ojo, .12); hacia('iris', t.iris, .12); hacia('gI', t.gir, .22); hacia('rub', t.rub, .2);
      hacia('alto', t.alto, .2); hacia('lag', t.lag, .25);
      hacia('ciY', t.ciY, .11); hacia('ciR', t.ciR, .11); hacia('cdY', t.cdY, .11); hacia('cdR', t.cdR, .11);

      /* Boca: la vocal que toca si esta hablando; si no, la de la expresion. */
      var ref = BOCAS[(fijo && fijo.boca) || vis || EXPRESIONES[nombreExpr].boca];
      var kb = r ? 1 : 1 - Math.exp(-dt / (vis ? .04 : .09));
      for (var i = 0; i < 18; i++) boca[i] = mezcla(boca[i], ref.p[i], kb);
      act.dientes = mezcla(act.dientes, ref.dientes, kb);

      var s = mov ? reloj : 0;

      /* Respiracion y vaiven */
      var resp = mov ? Math.sin(s * 1.45) * .5 + Math.sin(s * .53) * .5 : 0;
      gResp.setAttribute('transform', 'translate(0 ' + n1(resp * 1.1) + ')');
      if (mov) {
        p25.setAttribute('d', ondear(ops25, s, 7, 300, 680, 0));
        p24.setAttribute('d', ondear(ops24, s, 5, 310, 680, 1.3));
      }

      /* Paralaje: lo de atras va al reves y lo de adelante se adelanta. Eso da el volumen. */
      var x = act.px, y = act.py, habla = hablando && mov ? Math.sin(s * 8.3) * .6 : 0;
      gAtras.setAttribute('transform', 'translate(' + n1(-6 * x) + ' ' + n1(-2.5 * y) + ')');
      gCuello.setAttribute('transform', 'translate(' + n1(1.5 * x) + ' ' + n1(1 * y) + ')');
      gSombra.setAttribute('transform', 'translate(' + n1(5 * x + 7) + ' ' + n1(3 * y + 18 + act.alto) + ')');
      gCuerpo.setAttribute('transform', 'translate(' + n1(1.6 * x) + ' ' + n1(.6 * y) + ')');
      gCabeza.setAttribute('transform', 'translate(' + n1(7 * x) + ' ' + n1(4 * y + act.alto + resp * .7 + habla) + ') rotate(' + n1(act.gI + x * 1.5 + (mov ? Math.sin(s * .37) * .35 : 0)) + ' ' + PIVOTE_CABEZA[0] + ' ' + PIVOTE_CABEZA[1] + ')');
      var rasgos = 'translate(' + n1(3.6 * x) + ' ' + n1(2.4 * y) + ')';
      gRasgosA.setAttribute('transform', rasgos);
      gRasgosB.setAttribute('transform', rasgos);
      gRasgosC.setAttribute('transform', rasgos);
      gSombraPelo.setAttribute('transform', 'translate(' + n1(1.6 * x) + ' ' + n1(1 * y) + ')');
      gPelo.setAttribute('transform', 'translate(' + n1(1.2 * x) + ' ' + n1(.6 * y) + ')');
      gBrillo.setAttribute('transform', 'translate(' + n1(-5 * x) + ' ' + n1(-3 * y) + ')');
      gFlequillo.setAttribute('transform', 'translate(' + n1(3 * x) + ' ' + n1(1.8 * y) + ')');
      gOreja.setAttribute('transform', 'translate(' + n1(-2.6 * x) + ' ' + n1(.4 * y) + ')');
      var cuelga = mov ? Math.sin(s * 1.9) * 1.1 : 0;
      aretaD.setAttribute('transform', 'translate(' + n1(cuelga) + ' 0)');
      aretaI.setAttribute('transform', 'translate(' + n1(-1.6 * x - cuelga) + ' 0)');

      /* Ojos */
      var gx = act.mx * 8.5, gy = act.my * 4.8, esc = n1(act.ojo), irisEsc = n1(act.iris);
      gOjoI.setAttribute('transform', 'translate(' + CENTRO_OJO_I[0] + ' ' + CENTRO_OJO_I[1] + ') scale(' + esc + ') translate(' + -CENTRO_OJO_I[0] + ' ' + -CENTRO_OJO_I[1] + ')');
      gOjoD.setAttribute('transform', 'translate(' + CENTRO_OJO_D[0] + ' ' + CENTRO_OJO_D[1] + ') scale(' + esc + ') translate(' + -CENTRO_OJO_D[0] + ' ' + -CENTRO_OJO_D[1] + ')');
      irisI.setAttribute('transform', 'translate(' + n1(gx) + ' ' + n1(gy) + ') translate(240 315) scale(' + irisEsc + ') translate(-240 -315)');
      irisD.setAttribute('transform', 'translate(' + n1(gx) + ' ' + n1(gy) + ') translate(400 338) scale(' + irisEsc + ') translate(-400 -338)');

      /* En reposo el contorno queda algo arriba, para no recortar nada del dibujo de Figma. */
      var bajaI = act.pI * CAIDA_I, bajaD = act.pD * CAIDA_D;
      parpI.setAttribute('transform', 'translate(0 ' + n1(act.pI < .01 ? -8 : bajaI) + ')');
      parpD.setAttribute('transform', 'translate(0 ' + n1(act.pD < .01 ? -8 : bajaD) + ')');
      pestI.setAttribute('transform', 'translate(0 ' + n1(bajaI) + ')');
      pestD.setAttribute('transform', 'translate(0 ' + n1(bajaD) + ')');
      abiertoI.setAttribute('opacity', act.aI > .98 ? '0' : '1');
      abiertoD.setAttribute('opacity', act.aD > .98 ? '0' : '1');
      pestI.setAttribute('opacity', n1(1 - act.aI));
      pestD.setAttribute('opacity', n1(1 - act.aD));
      arcoI.setAttribute('opacity', n1(act.aI));
      arcoD.setAttribute('opacity', n1(act.aD));

      /* Cejas */
      cejaI.setAttribute('transform', 'translate(0 ' + n1(act.ciY) + ') rotate(' + n1(act.ciR) + ' ' + CENTRO_CEJA_I[0] + ' ' + CENTRO_CEJA_I[1] + ')');
      cejaD.setAttribute('transform', 'translate(0 ' + n1(act.cdY) + ') rotate(' + n1(act.cdR) + ' ' + CENTRO_CEJA_D[0] + ' ' + CENTRO_CEJA_D[1] + ')');

      rubor.setAttribute('opacity', n1(act.rub));

      /* Boca */
      var dBoca = trazoBoca(boca);
      bocaFondo.setAttribute('d', dBoca);
      bocaLinea.setAttribute('d', dBoca);
      bocaDientes.setAttribute('d', trazoDientes(boca, act.dientes));
      bocaDientes.setAttribute('opacity', act.dientes < .03 ? '0' : '1');

      /* Lagrima: nace bajo el ojo y baja por la mejilla. Quieta si no hay movimiento. */
      if (act.lag > .02) {
        var ciclo = mov ? (s * .42) % 1 : .35, op = mov ? act.lag * Math.min(1, ciclo * 7) * (1 - suave(.78, 1, ciclo)) : act.lag;
        gLagrima.setAttribute('transform', 'translate(' + n1(232 - ciclo * 2) + ' ' + n1(366 + ciclo * 62) + ')');
        gLagrima.setAttribute('opacity', n1(op));
      } else gLagrima.setAttribute('opacity', '0');
    }

    function programar() {
      /* Ritmo irregular: casi siempre entre 2 y 6 s; de vez en cuando uno doble. */
      if (reloj >= parpadeo.prox && parpadeo.ini < 0) {
        parpadeo.ini = reloj;
        if (!parpadeo.doble && Math.random() < .14) parpadeo.doble = true;
        parpadeo.prox = reloj + 2 + Math.random() * 4;
      }
      if (reloj >= micro.prox) {
        micro.x = (Math.random() - .5) * .5;
        micro.y = (Math.random() - .5) * .35;
        micro.prox = reloj + 1.6 + Math.random() * 3.5;
      }
    }

    function resuelve() {
      var p = promesas; promesas = [];
      p.forEach(function (f) { f(); });
    }
    /* El ritmo de la boca va con reloj propio: si faltan cuadros, el guion no se queda esperando. */
    function avanzaBoca() {
      var ahora = global.performance.now();
      if (ahora < visHasta) return;
      if (colaBoca.length) {
        var c = colaBoca.shift(), ritmo = colaBoca.length > 30 ? .65 : 1;
        vis = c.v; visHasta = ahora + c.ms * ritmo; hablando = true;
      } else if (vis) {
        vis = null;
      }
      if (!colaBoca.length && !vis && !enVoz && !bufVoz) {
        hablando = false;
        paraRitmo();
        resuelve();
      }
    }
    function iniciaRitmo() { if (!ritmoId) ritmoId = global.setInterval(avanzaBoca, 30); }
    function paraRitmo() { if (ritmoId) { global.clearInterval(ritmoId); ritmoId = 0; } }

    function cuadro(ms) {
      rafId = 0;
      if (destruido || pausado || document.hidden) return;
      var dt = ultimo ? Math.min((ms - ultimo) / 1000, .1) : .016;
      ultimo = ms; reloj += dt;
      if (!fijo) programar();
      pinta(dt, false);
      rafId = global.requestAnimationFrame(cuadro);
    }
    function arranca() {
      if (rafId || destruido || pausado || document.hidden) return;
      ultimo = 0;
      rafId = global.requestAnimationFrame(cuadro);
    }
    function detiene() { if (rafId) { global.cancelAnimationFrame(rafId); rafId = 0; } }
    function sinCuadros() {
      /* Sin cuadros no avanza la boca: un hablar() sin voz no debe quedar colgado. */
      colaBoca = []; vis = null;
      if (!enVoz && !bufVoz) { hablando = false; paraRitmo(); resuelve(); }
    }
    function alCambiarVisibilidad() {
      if (document.hidden) { detiene(); sinCuadros(); } else arranca();
    }
    document.addEventListener('visibilitychange', alCambiarVisibilidad);

    /* Cursor o toque: cerca del titere manda mas que lejos. */
    function alMover(ev) {
      if (reducido() || fijo) return;
      var r = svg.getBoundingClientRect();
      if (!r.width) return;
      var rx = Math.max(r.width, global.innerWidth * .4), ry = Math.max(r.height, global.innerHeight * .4);
      cursor.x = acota((ev.clientX - (r.left + r.width / 2)) / rx, -1, 1);
      cursor.y = acota((ev.clientY - (r.top + r.height * .42)) / ry, -1, 1);
      cursor.hasta = reloj + 3.5;
    }
    if (opciones.seguirCursor !== false) {
      global.addEventListener('pointermove', alMover, { passive: true });
      global.addEventListener('pointerdown', alMover, { passive: true });
    }

    /* ------- Voz ------- */
    function cortaOraciones(forzar) {
      var salida = [], m, re = /[^.!?…]+[.!?…]+["')\]]*\s*/g, fin = 0;
      while ((m = re.exec(bufVoz))) { salida.push(m[0].trim()); fin = re.lastIndex; }
      var resto = bufVoz.slice(fin);
      if (forzar && resto.trim()) { salida.push(resto.trim()); resto = ''; }
      bufVoz = forzar ? '' : resto;
      return salida;
    }
    function aTexto(frase) {
      colaBoca = colaBoca.concat(visemas(frase));
      if (document.hidden) sinCuadros(); else iniciaRitmo();
    }
    function dice(frase, turno) {
      var u = new global.SpeechSynthesisUtterance(frase);
      var v = eligeVoz();
      if (v) { u.voice = v; u.lang = v.lang; } else u.lang = 'es-419';
      u.rate = 1.02; u.pitch = 1.08;
      var conLimites = false, porTexto = false, empezo = false, cerrada = false, sinLimites = 0;
      function aTextoUnaVez() { if (!porTexto && turno === turnoVoz) { porTexto = true; aTexto(frase); } }
      /* Si la voz no arranca o no avisa las palabras, la boca sigue el texto. */
      var sinInicio = 0;
      function cierra() {
        if (cerrada) return;
        cerrada = true;
        global.clearTimeout(sinInicio); global.clearTimeout(sinLimites);
        if (turno !== turnoVoz) return;
        enVoz = Math.max(0, enVoz - 1);
        if (!enVoz && !colaBoca.length && !vis && !bufVoz) { hablando = false; resuelve(); }
      }
      sinInicio = global.setTimeout(function () {
        if (empezo || turno !== turnoVoz) return;
        /* Voz que nunca empieza: se descarta para no dejar la promesa colgada. */
        aTextoUnaVez();
        try { global.speechSynthesis.cancel(); } catch (e) {}
        cierra();
      }, 4000);
      u.onstart = function () {
        empezo = true; global.clearTimeout(sinInicio);
        if (turno !== turnoVoz) return;
        sinLimites = global.setTimeout(function () { if (!conLimites) aTextoUnaVez(); }, 700);
      };
      u.onboundary = function (e) {
        if (turno !== turnoVoz || (e.name && e.name !== 'word')) return;
        conLimites = true;
        if (porTexto) return;
        var desde = e.charIndex || 0, largo = e.charLength;
        var palabra = largo ? frase.substr(desde, largo) : (frase.slice(desde).match(/^\S+/) || [''])[0];
        colaBoca = visemas(palabra);
        visHasta = 0;
        hablando = true;
        iniciaRitmo();
      };
      u.onend = cierra;
      u.onerror = function (e) {
        if (!(e && (e.error === 'canceled' || e.error === 'interrupted'))) aTextoUnaVez();
        cierra();
      };
      enVoz++;
      vivas.push(u);   /* Chrome pierde eventos si recoge la utterance antes de terminar. */
      if (vivas.length > 12) vivas.shift();
      try { global.speechSynthesis.speak(u); } catch (e) { aTextoUnaVez(); cierra(); }
    }
    function vaciaVoz(forzar) {
      cortaOraciones(forzar).forEach(function (f) { dice(f, turnoVoz); });
      if (forzar && !enVoz && !colaBoca.length && !vis) { hablando = false; resuelve(); }
    }

    /* ------- API publica ------- */
    var api = {
      elemento: svg,
      expresion: function (nombre, op) {
        if (!EXPRESIONES[nombre]) return false;
        nombreExpr = nombre;
        if ((op && op.instantaneo) || reducido()) pinta(.016, true);
        return true;
      },
      /* Puede llamarse varias veces con trozos que van llegando. La promesa acaba al quedar en silencio. */
      hablar: function (texto) {
        texto = String(texto == null ? '' : texto);
        var promesa = new Promise(function (ok) { promesas.push(ok); });
        if (!texto.trim() && !bufVoz && !colaBoca.length && !enVoz && !vis) { resuelve(); return promesa; }
        hablando = true;
        if (vozActiva) {
          iniciaRitmo();
          bufVoz += texto;
          vaciaVoz(false);
          global.clearTimeout(temporizadorVoz);
          temporizadorVoz = global.setTimeout(function () { vaciaVoz(true); }, 450);
        } else {
          aTexto(texto);
        }
        return promesa;
      },
      callar: function () {
        turnoVoz++;
        colaBoca = []; vis = null; hablando = false; bufVoz = ''; enVoz = 0; visHasta = 0;
        paraRitmo();
        global.clearTimeout(temporizadorVoz);
        if (hayVoz()) { try { global.speechSynthesis.cancel(); } catch (e) {} }
        resuelve();
        if (reducido()) pinta(.016, true);
      },
      /* x e y van de -1 a 1; -1,-1 es arriba a la izquierda. El efecto dura 3,5 s si no se repite. */
      mirar: function (x, y) {
        cursor.x = acota(Number(x) || 0, -1, 1);
        cursor.y = acota(Number(y) || 0, -1, 1);
        cursor.hasta = reloj + 3.5;
        arranca();
        if (reducido()) pinta(.016, true);
      },
      voz: function (si) {
        if (si === undefined) return vozActiva;
        vozActiva = !!si && hayVoz();
        try { localStorage.setItem(CLAVE_VOZ, vozActiva ? '1' : '0'); } catch (e) {}
        if (!vozActiva) {
          turnoVoz++; enVoz = 0; bufVoz = '';
          global.clearTimeout(temporizadorVoz);
          if (hayVoz()) { try { global.speechSynthesis.cancel(); } catch (e) {} }
          if (!colaBoca.length && !vis) { hablando = false; resuelve(); }
        }
        return vozActiva;
      },
      hayVoz: hayVoz,
      /* Para ahorrar cuadros mientras no se ve, por ejemplo el avatar con el panel abierto. */
      pausar: function () { pausado = true; detiene(); },
      reanudar: function () { pausado = false; arranca(); },
      destruir: function () {
        destruido = true; detiene(); paraRitmo();
        document.removeEventListener('visibilitychange', alCambiarVisibilidad);
        global.removeEventListener('pointermove', alMover);
        global.removeEventListener('pointerdown', alMover);
        global.clearTimeout(temporizadorVoz);
        turnoVoz++;
        resuelve();
        if (svg.parentNode) svg.parentNode.removeChild(svg);
      },
      /* Solo para pruebas */
      _estado: function () { return { expresion: nombreExpr, vis: vis, cola: colaBoca.length, enVoz: enVoz, corriendo: !!rafId, hablando: hablando }; }
    };

    contenedor.appendChild(svg);
    if (opciones.expresion && EXPRESIONES[opciones.expresion]) nombreExpr = opciones.expresion;
    pinta(.016, true);
    if (hayVoz() && global.speechSynthesis.getVoices) global.speechSynthesis.getVoices();
    arranca();
    return api;
  }

  /* Boton de voz listo para poner en cualquier cabecera. Si el navegador no tiene voz, no aparece. */
  function botonVoz(titere, clase) {
    if (!hayVoz()) return null;
    var b = document.createElement('button');
    b.type = 'button';
    b.className = clase || 'indira-voz';
    function refresca() {
      var on = titere.voz();
      b.textContent = on ? 'Voz activada' : 'Activar voz';
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
    }
    b.addEventListener('click', function () { titere.voz(!titere.voz()); refresca(); });
    refresca();
    return b;
  }

  /* Archivo de una pose puntual, o null si ese estado no lleva pose. */
  function nombrePose(estado) {
    var e = ESTADOS[estado], nombre = e ? e.pose : estado;
    return nombre && POSES[nombre] ? nombre : null;
  }
  function rutaPose(ruta, estado) {
    var nombre = nombrePose(estado);
    return nombre ? (ruta || '') + POSES[nombre] : null;
  }
  /* Le da a la imagen de la pose su movimiento: <img data-mov="saluda">. */
  function animarPose(img, estado) {
    var e = ESTADOS[estado], nombre = (e && e.pose) || (POSES[estado] ? estado : null);
    if (!img) return;
    if (nombre) img.setAttribute('data-mov', MOVIMIENTO[nombre] || 'respira');
    else img.removeAttribute('data-mov');
  }

  global.IndiraTitere = {
    crear: crear, botonVoz: botonVoz, rutaPose: rutaPose, animarPose: animarPose,
    EXPRESIONES: Object.keys(EXPRESIONES), ESTADOS: ESTADOS, POSES: POSES
  };
})(window);
