'use client';
import clsx from 'clsx';
import { type ReactNode } from "react";

export interface Columna<T> { titulo: string; celda: (fila: T) => ReactNode; derecha?: boolean; className?: string }

// Tabla de datos: en pantallas pequenas se desplaza de lado, con la cabecera fija.

export function Tabla<T>({ columnas, filas, clave, vacio = 'Sin registros.' }:
  { columnas: Columna<T>[]; filas: T[]; clave: (fila: T, i: number) => string | number; vacio?: string }) {
  if (!filas.length) return <p className="px-5 py-8 text-center text-sm text-gris">{vacio}</p>;
  return (
    <div className="max-h-[32rem] overflow-auto">
      <table className="numeros w-full min-w-max text-sm">
        <thead className="sticky top-0 z-10 bg-fondo/95 backdrop-blur">
          <tr>
            {columnas.map((c) => (
              <th key={c.titulo} scope="col" className={clsx('px-4 py-2.5 text-left text-xs font-semibold text-gris', c.derecha && 'text-right', c.className)}>
                {c.titulo}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-borde">
          {filas.map((f, i) => (
            <tr key={clave(f, i)} className="hover:bg-azul-10/40">
              {columnas.map((c) => (
                <td key={c.titulo} className={clsx('px-4 py-2.5 align-top text-texto', c.derecha && 'text-right', c.className)}>{c.celda(f)}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
