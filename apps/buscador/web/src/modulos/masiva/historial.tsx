'use client';
// Historial de descargas de la carga masiva (ultimos archivos generados por la persona).
import { Download, History } from 'lucide-react';
import { useState } from 'react';
import { Aviso, Boton, Chip, Tabla, Tarjeta, Vacio, type Columna } from '@/components/ui';
import { ErrorApi, guardarArchivo } from '@/lib/api';
import { fBytes, fFecha, fNumero } from '@/lib/formato';
import { SECCIONES } from './documentos';
import { servicioMasiva } from './servicio';
import type { HistorialDescarga } from './tipos';

const nombreSeccion = (id: string) => SECCIONES.find((s) => s.id === id)?.nombre ?? id;

export function HistorialDescargas({ items, cargando }: { items: HistorialDescarga[] | null; cargando: boolean }) {
  const [descargando, setDescargando] = useState<number | null>(null);
  const [error, setError] = useState('');

  async function bajar(h: HistorialDescarga) {
    setDescargando(h.id); setError('');
    try { guardarArchivo(await servicioMasiva.descargar(h)); }
    catch (e) { setError(e instanceof ErrorApi ? e.message : 'No se pudo descargar el archivo.'); }
    finally { setDescargando(null); }
  }

  const columnas: Columna<HistorialDescarga>[] = [
    { titulo: 'Archivo', celda: (h) => <span className="font-medium">{h.archivo}</span> },
    { titulo: 'Fecha', celda: (h) => fFecha(h.fecha, true) },
    { titulo: 'Documentos', celda: (h) => fNumero(h.totalDnis), derecha: true },
    { titulo: 'Con resultados', celda: (h) => fNumero(h.dnisConResultados ?? null), derecha: true },
    { titulo: 'Secciones', celda: (h) => <div className="flex flex-wrap gap-1">{h.secciones.map((s) => <Chip key={s} tono="azul">{nombreSeccion(s)}</Chip>)}</div> },
    { titulo: 'Tamaño', celda: (h) => fBytes(h.tamanoBytes), derecha: true },
    { titulo: '', celda: (h) => <Boton variante="secundario" className="h-8 px-3" onClick={() => bajar(h)} cargando={descargando === h.id} aria-label={`Descargar ${h.archivo}`}><Download className="size-4" /></Boton>, derecha: true },
  ];

  return (
    <Tarjeta sinRelleno titulo={<h2 className="flex items-center gap-2 text-base font-semibold"><History className="size-[18px] text-azul" />Tus últimas descargas</h2>}>
      {error && <div className="p-4"><Aviso tono="error" alCerrar={() => setError('')}>{error}</Aviso></div>}
      {cargando ? <p className="px-5 py-8 text-center text-sm text-gris">Cargando historial…</p>
        : !items?.length ? <Vacio icono={<History className="size-5" />} titulo="Aún no tienes descargas">Los archivos que generes aparecerán aquí.</Vacio>
          : <Tabla columnas={columnas} filas={items} clave={(h) => h.id} />}
    </Tarjeta>
  );
}
