'use client';
import clsx from 'clsx';
import { Loader2 } from "lucide-react";
import { type ButtonHTMLAttributes } from "react";

type Variante = 'primario' | 'secundario' | 'fantasma' | 'peligro';
const VARIANTES: Record<Variante, string> = {
  primario: 'bg-azul text-white hover:bg-azul-oscuro shadow-sm',
  secundario: 'bg-white text-azul border border-borde hover:border-azul-50 hover:bg-azul-10',
  fantasma: 'text-azul hover:bg-azul-10',
  peligro: 'bg-white text-peligro border border-peligro/30 hover:bg-peligro-10',
};

export function Boton({ variante = 'primario', cargando, className, children, disabled, ...resto }:
  ButtonHTMLAttributes<HTMLButtonElement> & { variante?: Variante; cargando?: boolean }) {
  return (
    <button
      {...resto}
      disabled={disabled || cargando}
      className={clsx(
        'inline-flex items-center justify-center gap-2 rounded-lg px-4 h-10 text-sm font-semibold transition-colors',
        'disabled:opacity-55 disabled:cursor-not-allowed whitespace-nowrap',
        VARIANTES[variante], className,
      )}
    >
      {cargando && <Loader2 className="size-4 animate-spin" aria-hidden />}
      {children}
    </button>
  );
}
