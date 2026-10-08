'use client';
import clsx from 'clsx';
import { type InputHTMLAttributes } from "react";

export function Campo({ etiqueta, ayuda, error, className, id, ...resto }:
  InputHTMLAttributes<HTMLInputElement> & { etiqueta?: string; ayuda?: string; error?: string }) {
  const idCampo = id ?? resto.name;
  return (
    <label className={clsx('block', className)} htmlFor={idCampo}>
      {etiqueta && <span className="mb-1.5 block text-sm font-medium text-texto">{etiqueta}</span>}
      <input
        id={idCampo}
        {...resto}
        aria-invalid={Boolean(error) || undefined}
        className={clsx(
          'h-10 w-full rounded-lg border bg-white px-3 text-sm text-texto placeholder:text-gris/60 transition-colors',
          'focus:border-azul focus:outline-none focus:ring-2 focus:ring-azul/15',
          error ? 'border-peligro' : 'border-borde',
        )}
      />
      {error ? <span className="mt-1 block text-xs text-peligro">{error}</span>
        : ayuda && <span className="mt-1 block text-xs text-gris">{ayuda}</span>}
    </label>
  );
}
