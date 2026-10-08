'use client';
// Carga masiva (personas o empresas): 1) secciones, 2) documentos, 3) procesar y descargar el Excel.
import clsx from 'clsx';
import { Check, ClipboardPaste, FileDown, FileUp, Loader2, Play } from 'lucide-react';
import { useCallback, useEffect, useMemo, useState, type ChangeEvent } from 'react';
import { Aviso, Boton, Chip, Pestanas, Tarjeta } from '@/components/ui';
import { ErrorApi, guardarArchivo } from '@/lib/api';
import { fNumero } from '@/lib/formato';
import { useSesion } from '@/modulos/sesion/proveedor';
import { LIMITE_DOCUMENTOS, SECCIONES, TAMANO_MAXIMO, analizar, crearArchivo, plantilla, type TipoLista } from './documentos';
import { HistorialDescargas } from './historial';
import { servicioMasiva } from './servicio';
import type { HistorialDescarga } from './tipos';

type Fuente = 'pegar' | 'archivo';
type Fase = { tipo: 'lista' } | { tipo: 'subiendo'; porcentaje: number } | { tipo: 'procesando' } | { tipo: 'listo'; nombre: string };

function Paso({ numero, titulo, children, hecho }: { numero: number; titulo: string; children: React.ReactNode; hecho?: boolean }) {
  return (
    <Tarjeta titulo={
      <h2 className="flex items-center gap-3 text-base font-semibold text-texto">
        <span className={clsx('grid size-7 place-items-center rounded-full text-xs font-bold', hecho ? 'bg-verde text-white' : 'bg-azul text-white')}>
          {hecho ? <Check className="size-4" /> : numero}
        </span>{titulo}
      </h2>}>
      {children}
    </Tarjeta>
  );
}

export function CargaMasiva({ tipo }: { tipo: TipoLista }) {
  const { usuario, actualizarSaldo } = useSesion();
  const [secciones, setSecciones] = useState<string[]>(SECCIONES.map((s) => s.id));
  const [fuente, setFuente] = useState<Fuente>('pegar');
  const [texto, setTexto] = useState('');
  const [nombreArchivo, setNombreArchivo] = useState('');
  const [fase, setFase] = useState<Fase>({ tipo: 'lista' });
  const [error, setError] = useState('');
  const [historial, setHistorial] = useState<HistorialDescarga[] | null>(null);
  const [cargandoHistorial, setCargandoHistorial] = useState(true);

  const etiqueta = tipo === 'empresas' ? 'RUC' : 'documentos';
  const analisis = useMemo(() => analizar(texto, tipo), [texto, tipo]);
  const ocupado = fase.tipo === 'subiendo' || fase.tipo === 'procesando';

  const cargarHistorial = useCallback(() => {
    if (!usuario) return;
    setCargandoHistorial(true);
    servicioMasiva.historial(usuario.id).then(setHistorial).catch(() => setHistorial([])).finally(() => setCargandoHistorial(false));
  }, [usuario]);
  useEffect(cargarHistorial, [cargarHistorial]);

  async function leerArchivo(e: ChangeEvent<HTMLInputElement>) {
    const archivo = e.target.files?.[0];
    e.target.value = '';
    setError('');
    if (!archivo) return;
    if (!/\.(txt|csv)$/i.test(archivo.name)) { setError('Solo se aceptan archivos .txt o .csv.'); return; }
    if (archivo.size > TAMANO_MAXIMO) { setError('El archivo supera el límite de 5 MB.'); return; }
    setNombreArchivo(archivo.name);
    setTexto(await archivo.text());
  }

  const problema = !secciones.length ? 'Elige al menos una sección.'
    : !analisis.validos.length ? `Agrega al menos un ${tipo === 'empresas' ? 'RUC' : 'documento'} válido.`
      : analisis.validos.length > LIMITE_DOCUMENTOS ? `El máximo es ${fNumero(LIMITE_DOCUMENTOS)} por carga.` : null;

  async function procesar() {
    if (problema || !usuario) return;
    setError('');
    setFase({ tipo: 'subiendo', porcentaje: 0 });
    const archivo = crearArchivo(analisis.validos, tipo === 'empresas' ? 'RUC' : 'Documentos');
    try {
      const resultado = await servicioMasiva.procesar(tipo, archivo, secciones, (p) =>
        setFase(p >= 100 ? { tipo: 'procesando' } : { tipo: 'subiendo', porcentaje: p }));
      guardarArchivo(resultado);
      setFase({ tipo: 'listo', nombre: resultado.nombre });
      await servicioMasiva.guardarEnHistorial(resultado, secciones, analisis.validos.length).catch(() => null);
      cargarHistorial();
    } catch (e) {
      setError(e instanceof ErrorApi ? e.message : 'No se pudo procesar la carga.');
      setFase({ tipo: 'lista' });
    } finally {
      actualizarSaldo();
    }
  }

  return (
    <div className="space-y-5">
      <Paso numero={1} titulo="Elige qué información incluir" hecho={secciones.length > 0}>
        <div className="mb-3 flex justify-end">
          <button className="text-sm font-semibold text-azul hover:underline" onClick={() => setSecciones(secciones.length === SECCIONES.length ? [] : SECCIONES.map((s) => s.id))}>
            {secciones.length === SECCIONES.length ? 'Quitar todas' : 'Elegir todas'}
          </button>
        </div>
        <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-5">
          {SECCIONES.map((s) => {
            const marcada = secciones.includes(s.id);
            return (
              <label key={s.id} className={clsx('flex cursor-pointer gap-3 rounded-lg border p-3 transition-colors', marcada ? 'border-azul bg-azul-10/60' : 'border-borde hover:border-azul-25')}>
                <input type="checkbox" className="mt-0.5 size-4 accent-[var(--color-azul)]" checked={marcada}
                  onChange={() => setSecciones(marcada ? secciones.filter((x) => x !== s.id) : [...secciones, s.id])} />
                <span><span className="block text-sm font-semibold text-texto">{s.nombre}</span><span className="block text-xs text-gris">{s.detalle}</span></span>
              </label>
            );
          })}
        </div>
      </Paso>

      <Paso numero={2} titulo={`Agrega los ${etiqueta}`} hecho={analisis.validos.length > 0}>
        <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
          <Pestanas<Fuente> valor={fuente} alCambiar={setFuente} opciones={[
            { id: 'pegar', texto: 'Pegar lista', icono: <ClipboardPaste className="size-4" /> },
            { id: 'archivo', texto: 'Subir archivo', icono: <FileUp className="size-4" /> },
          ]} />
          <Boton variante="fantasma" onClick={() => guardarArchivo({ blob: plantilla(tipo), nombre: plantilla(tipo).name })}><FileDown className="size-4" />Descargar plantilla</Boton>
        </div>
        {fuente === 'pegar' ? (
          <textarea value={texto} onChange={(e) => { setTexto(e.target.value); setNombreArchivo(''); }} rows={7} disabled={ocupado}
            placeholder={tipo === 'empresas' ? 'Pega los RUC, uno por línea o separados por comas' : 'Pega los DNI u otros documentos, uno por línea o separados por comas'}
            className="numeros w-full rounded-lg border border-borde bg-white p-3 text-sm focus:border-azul focus:outline-none focus:ring-2 focus:ring-azul/15" />
        ) : (
          <label className="flex cursor-pointer flex-col items-center justify-center gap-2 rounded-lg border-2 border-dashed border-azul-25 bg-azul-10/30 px-6 py-10 text-center hover:border-azul">
            <FileUp className="size-7 text-azul" />
            <span className="font-semibold text-texto">{nombreArchivo || 'Elige un archivo .txt o .csv'}</span>
            <span className="text-xs text-gris">Un {tipo === 'empresas' ? 'RUC' : 'documento'} por línea. Máximo 5 MB.</span>
            <input type="file" accept=".txt,.csv,text/plain,text/csv" className="sr-only" onChange={leerArchivo} disabled={ocupado} />
          </label>
        )}
        {(analisis.validos.length > 0 || analisis.invalidos.length > 0) && (
          <div className="numeros mt-4 flex flex-wrap items-center gap-2 text-sm">
            {analisis.porTipo.map((t) => <Chip key={t.nombre} tono="verde">{fNumero(t.cantidad)} {t.nombre}</Chip>)}
            {analisis.duplicados > 0 && <Chip>{fNumero(analisis.duplicados)} repetidos (se omiten)</Chip>}
            {analisis.invalidos.length > 0 && <Chip tono="ambar">{fNumero(analisis.invalidos.length)} no válidos: {analisis.invalidos.slice(0, 3).join(', ')}{analisis.invalidos.length > 3 ? '…' : ''}</Chip>}
          </div>
        )}
      </Paso>

      <Paso numero={3} titulo="Procesa y descarga el Excel" hecho={fase.tipo === 'listo'}>
        {error && <div className="mb-4"><Aviso tono="error" alCerrar={() => setError('')}>{error}</Aviso></div>}
        {fase.tipo === 'listo' && <div className="mb-4"><Aviso tono="exito">Listo: se descargó <strong>{fase.nombre}</strong>. También quedó en tu historial.</Aviso></div>}
        <div className="flex flex-wrap items-center gap-4">
          <Boton onClick={procesar} disabled={Boolean(problema) || ocupado} cargando={ocupado} className="h-11 px-6">
            {!ocupado && <Play className="size-4" />}Procesar {analisis.validos.length ? fNumero(analisis.validos.length) : ''} {etiqueta}
          </Boton>
          {problema && !ocupado && <span className="text-sm text-gris">{problema}</span>}
          {ocupado && (
            <div className="min-w-56 flex-1">
              <p className="mb-1.5 flex items-center gap-2 text-sm text-gris">
                <Loader2 className="size-4 animate-spin text-azul" />
                {fase.tipo === 'subiendo' ? `Enviando la lista… ${fase.porcentaje}%` : 'Consultando en el servidor. Puede tardar unos minutos.'}
              </p>
              <div className="h-2 overflow-hidden rounded-full bg-azul-10">
                {fase.tipo === 'subiendo'
                  ? <div className="h-full rounded-full bg-azul transition-[width]" style={{ width: `${fase.porcentaje}%` }} />
                  : <div className="h-full w-1/3 rounded-full bg-azul [animation:barrido_1.2s_ease-in-out_infinite]" />}
              </div>
            </div>
          )}
        </div>
      </Paso>

      <HistorialDescargas items={historial} cargando={cargandoHistorial} />
    </div>
  );
}
