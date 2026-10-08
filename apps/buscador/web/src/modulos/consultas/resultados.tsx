'use client';
// Presentacion de resultados: resumen + una tarjeta por seccion (deudas, lineas, calificaciones, laboral, telefonos).
import type { ReactNode } from 'react';
import { Banknote, Briefcase, CreditCard, Gauge, Phone } from 'lucide-react';
import { Chip, Tabla, Tarjeta, type Columna } from '@/components/ui';
import { fFecha, fMoneda, fNumero, fPeriodo, fTexto, nombreCompleto } from '@/lib/formato';
import type { Calificacion, Deuda, LineaCredito, Movil, Sueldo } from './tipos';

export function tonoCalificacion(c: string | null | undefined): 'verde' | 'ambar' | 'peligro' | 'neutro' {
  const v = String(c ?? '').toUpperCase();
  if (!v) return 'neutro';
  if (v.includes('NOR') || v === '0') return 'verde';
  if (v.includes('CPP') || v === '1') return 'ambar';
  return 'peligro';
}

export function Seccion({ titulo, icono, cantidad, children }: { titulo: string; icono: ReactNode; cantidad: number; children: ReactNode }) {
  return (
    <Tarjeta sinRelleno className="aparecer overflow-hidden"
      titulo={<h2 className="flex items-center gap-2.5 text-base font-semibold text-texto"><span className="text-azul">{icono}</span>{titulo}<Chip tono={cantidad ? 'azul' : 'neutro'}>{fNumero(cantidad)}</Chip></h2>}>
      {children}
    </Tarjeta>
  );
}

const colDeudas: Columna<Deuda>[] = [
  { titulo: 'Periodo', celda: (d) => fPeriodo(d.periodo) },
  { titulo: 'Entidad', celda: (d) => fTexto(d.entidad), className: 'max-w-64' },
  { titulo: 'Tipo de deuda', celda: (d) => fTexto(d.tipoDeuda) },
  { titulo: 'Días', celda: (d) => fNumero(d.dias), derecha: true },
  { titulo: 'Calificación', celda: (d) => d.calificacion ? <Chip tono={tonoCalificacion(d.calificacion)}>{d.calificacion}</Chip> : '—' },
  { titulo: 'Saldo', celda: (d) => <span className="font-semibold">{fMoneda(d.saldo)}</span>, derecha: true },
];
const colLineas: Columna<LineaCredito>[] = [
  { titulo: 'Periodo', celda: (l) => fPeriodo(l.periodo) },
  { titulo: 'Entidad', celda: (l) => fTexto(l.entidad) },
  { titulo: 'Tipo', celda: (l) => fTexto(l.tipo) },
  { titulo: 'Línea', celda: (l) => fMoneda(l.lineaCreditoMonto), derecha: true },
  { titulo: 'Utilizada', celda: (l) => fMoneda(l.lineaUtilizada), derecha: true },
  { titulo: 'Disponible', celda: (l) => fMoneda(l.lineaNoUtilizada), derecha: true },
];
const pct = (n: number | null) => (n == null ? '—' : `${n}%`);
const colCalificaciones: Columna<Calificacion>[] = [
  { titulo: 'Periodo', celda: (c) => fPeriodo(c.periodo) },
  { titulo: 'Normal', celda: (c) => pct(c.nor), derecha: true },
  { titulo: 'CPP', celda: (c) => pct(c.cpp), derecha: true },
  { titulo: 'Deficiente', celda: (c) => pct(c.def), derecha: true },
  { titulo: 'Dudoso', celda: (c) => pct(c.dud), derecha: true },
  { titulo: 'Pérdida', celda: (c) => pct(c.per), derecha: true },
  { titulo: 'Entidades', celda: (c) => fTexto(c.reportan), derecha: true },
];
const colSueldos: Columna<Sueldo>[] = [
  { titulo: 'Periodo', celda: (s) => fPeriodo(s.periodo) },
  { titulo: 'Empresa', celda: (s) => <span>{fTexto(s.empresa)}<span className="block text-xs text-gris">{s.ruc ? `RUC ${s.ruc}` : ''}</span></span> },
  { titulo: 'Sueldo', celda: (s) => fMoneda(s.montoSueldo), derecha: true },
  { titulo: 'Gratif./bono', celda: (s) => fMoneda(s.gratifBono), derecha: true },
  { titulo: 'Ingreso anual est.', celda: (s) => fMoneda(s.ingresoEstimadoAnual), derecha: true },
  { titulo: 'Rango', celda: (s) => fTexto(s.rangoSueldo) },
  { titulo: 'Nivel', celda: (s) => fTexto(s.nivelIngreso) },
];
export const colMoviles: Columna<Movil>[] = [
  { titulo: 'Teléfono', celda: (m) => <span className="font-semibold">{fTexto(m.telefono)}</span> },
  { titulo: 'Titular', celda: (m) => nombreCompleto(m.prenombres, m.apePat, m.apeMat) },
  { titulo: 'Documento', celda: (m) => fTexto(m.documento) },
  { titulo: 'Operadora', celda: (m) => fTexto(m.empresaOperadora) },
  { titulo: 'Plan', celda: (m) => fTexto(m.planMovil) },
  { titulo: 'Modalidad', celda: (m) => fTexto(m.modalidad) },
  { titulo: 'Alta', celda: (m) => fFecha(m.fechaAlta) },
  { titulo: 'Periodo', celda: (m) => fPeriodo(m.periodo) },
];

// Para tablas sin tipo fijo (la API de empresas devuelve telefonos y sueldos como objetos libres)
function columnasLibres(filas: Record<string, unknown>[]): Columna<Record<string, unknown>>[] {
  const claves = [...new Set(filas.flatMap((f) => Object.keys(f)))].filter((k) => !/^(id|fechaCarga)$/i.test(k)).slice(0, 10);
  return claves.map((k) => ({
    titulo: k.replace(/([A-Z])/g, ' $1').replace(/^./, (c) => c.toUpperCase()),
    celda: (f) => {
      const v = f[k];
      if (typeof v === 'number') return /monto|sueldo|saldo|ingreso|bono/i.test(k) ? fMoneda(v) : fNumero(v);
      if (k.toLowerCase() === 'periodo') return fPeriodo(String(v ?? ''));
      return fTexto(v == null ? null : String(v));
    },
  }));
}

export interface Secciones {
  deudas: Deuda[]; lineasCredito: LineaCredito[]; calificaciones: Calificacion[];
  sueldos: Sueldo[] | Record<string, unknown>[]; moviles: Movil[] | Record<string, unknown>[];
}

export function Resumen({ s }: { s: Secciones }) {
  const ultimoPeriodo = s.deudas.reduce((m, d) => (d.periodo > m ? d.periodo : m), '');
  const deudasRecientes = s.deudas.filter((d) => d.periodo === ultimoPeriodo);
  const total = deudasRecientes.reduce((t, d) => t + (d.saldo ?? 0), 0);
  const entidades = new Set(deudasRecientes.map((d) => d.entidad)).size;
  const orden = ['verde', 'ambar', 'peligro'] as const;
  const peor = s.deudas.reduce<string | null>((p, d) => {
    if (!d.calificacion) return p;
    return !p || orden.indexOf(tonoCalificacion(d.calificacion) as typeof orden[number]) > orden.indexOf(tonoCalificacion(p) as typeof orden[number]) ? d.calificacion : p;
  }, null);
  const sueldo = (s.sueldos as Sueldo[]).find((x) => typeof x?.montoSueldo === 'number')?.montoSueldo ?? null;
  const items = [
    { titulo: 'Deuda total', valor: ultimoPeriodo ? fMoneda(total) : '—', nota: ultimoPeriodo ? fPeriodo(ultimoPeriodo) : 'Sin deudas reportadas', icono: <Banknote className="size-4" /> },
    { titulo: 'Entidades', valor: fNumero(entidades), nota: 'en el último periodo', icono: <CreditCard className="size-4" /> },
    { titulo: 'Peor calificación', valor: peor ?? '—', nota: 'en el historial', icono: <Gauge className="size-4" />, tono: tonoCalificacion(peor) },
    { titulo: 'Sueldo reportado', valor: fMoneda(sueldo), nota: 'último registro', icono: <Briefcase className="size-4" /> },
  ];
  return (
    <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
      {items.map((i) => (
        <div key={i.titulo} className="aparecer rounded-xl border border-borde bg-white p-4 shadow-tarjeta">
          <p className="flex items-center gap-2 text-xs font-semibold text-gris"><span className="text-azul">{i.icono}</span>{i.titulo}</p>
          <p className={`numeros mt-2 text-xl font-semibold ${i.tono === 'peligro' ? 'text-peligro' : i.tono === 'ambar' ? 'text-ambar' : 'text-texto'}`}>{i.valor}</p>
          <p className="mt-0.5 text-xs text-gris">{i.nota}</p>
        </div>
      ))}
    </div>
  );
}

export function SeccionesResultado({ s, tipadas = true }: { s: Secciones; tipadas?: boolean }) {
  return (
    <div className="space-y-4">
      <Seccion titulo="Deudas" icono={<Banknote className="size-[18px]" />} cantidad={s.deudas.length}>
        <Tabla columnas={colDeudas} filas={s.deudas} clave={(d, i) => `${d.periodo}-${d.codigoSbs}-${i}`} vacio="No registra deudas." />
      </Seccion>
      <Seccion titulo="Líneas de crédito" icono={<CreditCard className="size-[18px]" />} cantidad={s.lineasCredito.length}>
        <Tabla columnas={colLineas} filas={s.lineasCredito} clave={(l, i) => `${l.periodo}-${i}`} vacio="No registra líneas de crédito." />
      </Seccion>
      <Seccion titulo="Calificaciones" icono={<Gauge className="size-[18px]" />} cantidad={s.calificaciones.length}>
        <Tabla columnas={colCalificaciones} filas={s.calificaciones} clave={(c, i) => `${c.periodo}-${i}`} vacio="No registra calificaciones." />
      </Seccion>
      <Seccion titulo="Información laboral" icono={<Briefcase className="size-[18px]" />} cantidad={s.sueldos.length}>
        {tipadas
          ? <Tabla columnas={colSueldos} filas={s.sueldos as Sueldo[]} clave={(x, i) => `${x.periodo}-${i}`} vacio="No registra información laboral." />
          : <Tabla columnas={columnasLibres(s.sueldos as Record<string, unknown>[])} filas={s.sueldos as Record<string, unknown>[]} clave={(_, i) => i} vacio="No registra información laboral." />}
      </Seccion>
      <Seccion titulo="Teléfonos" icono={<Phone className="size-[18px]" />} cantidad={s.moviles.length}>
        {tipadas
          ? <Tabla columnas={colMoviles} filas={s.moviles as Movil[]} clave={(m, i) => `${m.telefono}-${i}`} vacio="No registra teléfonos." />
          : <Tabla columnas={columnasLibres(s.moviles as Record<string, unknown>[])} filas={s.moviles as Record<string, unknown>[]} clave={(_, i) => i} vacio="No registra teléfonos." />}
      </Seccion>
    </div>
  );
}
