'use client';
// Barra de busqueda principal de las consultas individuales.
import { Search } from 'lucide-react';
import { useState, type FormEvent } from 'react';
import { Boton } from '@/components/ui';

export function BarraBusqueda({ etiqueta, placeholder, valorInicial = '', validar, alBuscar, cargando, numerica = true }: {
  etiqueta: string; placeholder: string; valorInicial?: string; numerica?: boolean; cargando?: boolean;
  validar: (v: string) => string | null; alBuscar: (v: string) => void;
}) {
  const [valor, setValor] = useState(valorInicial);
  const [error, setError] = useState('');

  function enviar(e: FormEvent) {
    e.preventDefault();
    const limpio = numerica ? valor.replace(/\s/g, '') : valor.trim();
    const problema = validar(limpio);
    setError(problema ?? '');
    if (!problema) alBuscar(limpio);
  }

  return (
    <form onSubmit={enviar} className="flex flex-col gap-2 sm:flex-row sm:items-start" noValidate>
      <label className="relative flex-1">
        <span className="sr-only">{etiqueta}</span>
        <Search className="pointer-events-none absolute left-3.5 top-[22px] size-5 -translate-y-1/2 text-gris" aria-hidden />
        <input
          value={valor} onChange={(e) => { setValor(e.target.value); setError(''); }}
          inputMode={numerica ? 'numeric' : 'text'} placeholder={placeholder} aria-invalid={Boolean(error) || undefined}
          className={`numeros h-11 w-full rounded-lg border bg-white pl-11 pr-3 text-base text-texto placeholder:text-gris/60 focus:border-azul focus:outline-none focus:ring-2 focus:ring-azul/15 ${error ? 'border-peligro' : 'border-borde'}`}
        />
        {error && <span className="mt-1 block text-xs text-peligro">{error}</span>}
      </label>
      <Boton type="submit" cargando={cargando} className="h-11 px-6">Consultar</Boton>
    </form>
  );
}
