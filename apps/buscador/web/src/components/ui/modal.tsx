'use client';
import clsx from 'clsx';
import { X } from "lucide-react";
import { useEffect, useRef, type ReactNode } from "react";

export function Modal({ abierto, titulo, alCerrar, children, ancho = 'max-w-lg' }:
  { abierto: boolean; titulo: string; alCerrar: () => void; children: ReactNode; ancho?: string }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (abierto && !d.open) d.showModal();
    if (!abierto && d.open) d.close();
  }, [abierto]);
  return (
    <dialog ref={ref} onClose={alCerrar} className={clsx('m-auto w-[calc(100%-2rem)] rounded-xl p-0 shadow-2xl backdrop:bg-azul-noche/55 backdrop:backdrop-blur-sm', ancho)}>
      {abierto && (
        <div className="aparecer">
          <header className="flex items-center justify-between border-b border-borde px-5 py-4">
            <h2 className="text-lg font-semibold text-texto">{titulo}</h2>
            <button onClick={alCerrar} aria-label="Cerrar" className="rounded-md p-1 text-gris hover:bg-fondo"><X className="size-5" /></button>
          </header>
          <div className="p-5">{children}</div>
        </div>
      )}
    </dialog>
  );
}
