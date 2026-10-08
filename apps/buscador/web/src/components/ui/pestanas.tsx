'use client';
import clsx from 'clsx';
import { type ReactNode } from "react";

export function Pestanas<T extends string>({ opciones, valor, alCambiar }:
  { opciones: { id: T; texto: string; icono?: ReactNode }[]; valor: T; alCambiar: (v: T) => void }) {
  return (
    <div role="tablist" className="inline-flex max-w-full gap-1 overflow-x-auto rounded-lg bg-azul-10 p-1">
      {opciones.map((o) => (
        <button
          key={o.id} role="tab" aria-selected={valor === o.id} onClick={() => alCambiar(o.id)}
          className={clsx(
            'inline-flex items-center gap-2 whitespace-nowrap rounded-md px-3.5 h-9 text-sm font-semibold transition-colors',
            valor === o.id ? 'bg-white text-azul shadow-sm' : 'text-gris hover:text-azul',
          )}
        >
          {o.icono}{o.texto}
        </button>
      ))}
    </div>
  );
}
