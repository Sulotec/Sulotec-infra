'use client';
import clsx from 'clsx';
import { AlertTriangle, CheckCircle2, Info, Loader2, X } from "lucide-react";
import { type ReactNode } from "react";

type TonoChip = 'neutro' | 'azul' | 'verde' | 'ambar' | 'peligro';
const TONOS: Record<TonoChip, string> = {
  neutro: 'bg-fondo text-gris', azul: 'bg-azul-10 text-azul', verde: 'bg-verde-10 text-verde',
  ambar: 'bg-ambar-10 text-ambar', peligro: 'bg-peligro-10 text-peligro',
};

export function Chip({ tono = 'neutro', children, className }: { tono?: TonoChip; children: ReactNode; className?: string }) {
  return <span className={clsx('inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-semibold', TONOS[tono], className)}>{children}</span>;
}

export function Aviso({ tono = 'info', children, alCerrar }: { tono?: 'info' | 'exito' | 'error' | 'alerta'; children: ReactNode; alCerrar?: () => void }) {
  const estilos = {
    info: ['bg-azul-10 text-azul-oscuro border-azul-25', Info],
    exito: ['bg-verde-10 text-verde border-verde/20', CheckCircle2],
    error: ['bg-peligro-10 text-peligro border-peligro/20', AlertTriangle],
    alerta: ['bg-ambar-10 text-ambar border-ambar/20', AlertTriangle],
  } as const;
  const [clase, Icono] = estilos[tono];
  return (
    <div role={tono === 'error' ? 'alert' : 'status'} className={clsx('aparecer flex items-start gap-3 rounded-lg border px-4 py-3 text-sm', clase)}>
      <Icono className="mt-0.5 size-4 shrink-0" aria-hidden />
      <div className="flex-1">{children}</div>
      {alCerrar && <button onClick={alCerrar} aria-label="Cerrar aviso" className="opacity-70 hover:opacity-100"><X className="size-4" /></button>}
    </div>
  );
}

export function Vacio({ icono, titulo, children }: { icono: ReactNode; titulo: string; children?: ReactNode }) {
  return (
    <div className="flex flex-col items-center justify-center gap-2 px-6 py-12 text-center">
      <div className="grid size-12 place-items-center rounded-full bg-azul-10 text-azul">{icono}</div>
      <p className="font-semibold text-texto">{titulo}</p>
      {children && <div className="max-w-md text-sm text-gris">{children}</div>}
    </div>
  );
}

export function Cargando({ texto = 'Consultando…' }: { texto?: string }) {
  return (
    <div className="flex items-center justify-center gap-3 py-12 text-sm text-gris" role="status">
      <Loader2 className="size-5 animate-spin text-azul" aria-hidden />{texto}
    </div>
  );
}
