'use client';
import { Boton } from './boton';
import { ChevronLeft, ChevronRight } from "lucide-react";

export function Paginacion({ pagina, tamano, total, alCambiar }: { pagina: number; tamano: number; total: number; alCambiar: (p: number) => void }) {
  const paginas = Math.max(1, Math.ceil(total / tamano));
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 border-t border-borde px-5 py-3 text-sm text-gris">
      <span className="numeros">{total.toLocaleString('es-PE')} en total</span>
      <div className="flex items-center gap-2">
        <Boton variante="secundario" className="h-8 px-2.5" disabled={pagina <= 1} onClick={() => alCambiar(pagina - 1)} aria-label="Página anterior"><ChevronLeft className="size-4" /></Boton>
        <span className="numeros min-w-24 text-center">Página {pagina} de {paginas}</span>
        <Boton variante="secundario" className="h-8 px-2.5" disabled={pagina >= paginas} onClick={() => alCambiar(pagina + 1)} aria-label="Página siguiente"><ChevronRight className="size-4" /></Boton>
      </div>
    </div>
  );
}
