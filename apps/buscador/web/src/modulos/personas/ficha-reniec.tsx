'use client';
// Ficha RENIEC: foto, firma y datos de la persona.
import { IdCard } from 'lucide-react';
import { Tarjeta } from '@/components/ui';
import { nombreCompleto } from '@/lib/formato';
import type { ResultadoReniec } from './tipos';

function Dato({ titulo, valor }: { titulo: string; valor?: string }) {
  return (
    <div>
      <dt className="text-xs text-gris">{titulo}</dt>
      <dd className="mt-0.5 text-sm font-medium text-texto">{valor && valor.trim() ? valor : '—'}</dd>
    </div>
  );
}

export function FichaReniec({ r }: { r: ResultadoReniec }) {
  const p = r.datos?.listaAni?.[0];
  if (!r.encontrado || !p) {
    return <Tarjeta titulo="RENIEC"><p className="text-sm text-gris">RENIEC no devolvió datos para el DNI {r.dni}.</p></Tarjeta>;
  }
  const imagen = (b64?: string) => (b64 ? (b64.startsWith('data:') ? b64 : `data:image/jpeg;base64,${b64}`) : null);
  const foto = imagen(r.datos?.foto);
  const firma = imagen(r.datos?.firma);
  return (
    <Tarjeta className="aparecer" titulo={<h2 className="flex items-center gap-2 text-base font-semibold"><IdCard className="size-[18px] text-azul" />Datos RENIEC</h2>}>
      <div className="flex flex-col gap-6 sm:flex-row">
        <div className="flex shrink-0 flex-row gap-3 sm:flex-col">
          {foto ? <img src={foto} alt={`Foto de DNI ${r.dni}`} className="h-36 w-28 rounded-lg border border-borde object-cover" />
            : <div className="grid h-36 w-28 place-items-center rounded-lg bg-fondo text-xs text-gris">Sin foto</div>}
          {firma && <img src={firma} alt="Firma" className="h-12 w-28 rounded border border-borde bg-white object-contain" />}
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-lg font-semibold text-texto">{nombreCompleto(p.preNombres, p.apePaterno, p.apeMaterno)}</p>
          <p className="numeros text-sm text-gris">DNI {p.nuDni ?? r.dni}{p.feFallecimiento ? ` · Fallecido el ${p.feFallecimiento}` : ''}</p>
          <dl className="mt-4 grid grid-cols-2 gap-x-6 gap-y-3 md:grid-cols-3">
            <Dato titulo="Fecha de nacimiento" valor={p.feNacimiento} />
            <Dato titulo="Edad" valor={p.nuEdad} />
            <Dato titulo="Sexo" valor={p.sexo} />
            <Dato titulo="Estado civil" valor={p.estadoCivil} />
            <Dato titulo="Grado de instrucción" valor={p.gradoInstruccion} />
            <Dato titulo="Restricción" valor={p.deRestriccion} />
            <Dato titulo="Dirección" valor={p.desDireccion} />
            <Dato titulo="Distrito" valor={p.distDireccion ?? p.distrito} />
            <Dato titulo="Provincia / Departamento" valor={[p.provDireccion ?? p.provincia, p.depaDireccion ?? p.departamento].filter(Boolean).join(' / ')} />
            <Dato titulo="Padre" valor={p.nomPadre} />
            <Dato titulo="Madre" valor={p.nomMadre} />
            <Dato titulo="Emisión / Caducidad" valor={[p.feEmision, p.feCaducidad].filter(Boolean).join(' / ')} />
          </dl>
        </div>
      </div>
    </Tarjeta>
  );
}
