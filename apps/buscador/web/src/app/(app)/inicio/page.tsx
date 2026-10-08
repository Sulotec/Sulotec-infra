'use client';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState, type FormEvent } from 'react';
import { ArrowRight, Building2, ClipboardList, FileSpreadsheet, Search, UserSearch, Users } from 'lucide-react';
import { useSesion } from '@/modulos/sesion/proveedor';
import { Aviso } from '@/components/ui';

export default function Inicio() {
  const { usuario, esAdmin, saldo } = useSesion();
  const router = useRouter();
  const [texto, setTexto] = useState('');
  const [aviso, setAviso] = useState('');

  function buscar(e: FormEvent) {
    e.preventDefault();
    const v = texto.replace(/\s/g, '');
    if (/^\d{8}$/.test(v)) router.push(`/personas?dni=${v}`);
    else if (/^(10|15|16|17|20)\d{9}$/.test(v)) router.push(`/empresas?ruc=${v}`);
    else if (/^9\d{8}$/.test(v)) router.push(`/personas?telefono=${v}`);
    else setAviso('Escribe un DNI (8 dígitos), un RUC (11 dígitos) o un celular (9 dígitos).');
  }

  const accesos = [
    { href: '/personas', titulo: 'Personas', texto: 'Consulta por DNI o teléfono, con RENIEC, deudas, líneas, laboral y teléfonos.', icono: UserSearch },
    { href: '/empresas', titulo: 'Empresas', texto: 'Consulta por RUC o razón social.', icono: Building2 },
    { href: '/personas/masiva', titulo: 'Carga masiva', texto: 'Hasta 10 000 documentos en un Excel.', icono: FileSpreadsheet },
    ...(esAdmin ? [
      { href: '/admin/usuarios', titulo: 'Usuarios y tokens', texto: 'Crea cuentas, asigna roles y tokens.', icono: Users },
      { href: '/admin/auditoria', titulo: 'Auditoría', texto: 'Quién consultó qué y cuándo.', icono: ClipboardList },
    ] : []),
  ];

  return (
    <div className="space-y-8">
      <section className="aparecer relative overflow-hidden rounded-2xl bg-azul-noche px-6 py-9 text-white sm:px-10">
        <div className="absolute -right-24 -top-24 size-80 rounded-full bg-azul-claro/35 blur-3xl" aria-hidden />
        <p className="relative text-sm text-azul-25">Hola, {usuario?.nombreCompleto.split(' ')[0]}</p>
        <h1 className="relative mt-1 text-2xl font-semibold tracking-tight sm:text-3xl">¿Qué quieres consultar hoy?</h1>
        <form onSubmit={buscar} className="relative mt-6 flex max-w-2xl flex-col gap-2 sm:flex-row">
          <label className="relative flex-1">
            <span className="sr-only">DNI, RUC o celular</span>
            <Search className="pointer-events-none absolute left-4 top-1/2 size-5 -translate-y-1/2 text-gris" aria-hidden />
            <input
              value={texto} onChange={(e) => { setTexto(e.target.value); setAviso(''); }} inputMode="numeric" autoFocus
              placeholder="DNI, RUC o celular"
              className="numeros h-13 w-full rounded-xl border-0 bg-white pl-12 pr-4 text-base text-texto placeholder:text-gris/70 focus:outline-none focus:ring-4 focus:ring-white/25"
            />
          </label>
          <button className="inline-flex h-13 items-center justify-center gap-2 rounded-xl bg-rojo px-6 font-semibold text-white hover:brightness-110">Buscar<ArrowRight className="size-4" /></button>
        </form>
        {saldo && !saldo.ilimitado && <p className="relative mt-3 text-xs text-azul-25">Te quedan {saldo.saldo.toLocaleString('es-PE')} tokens. Cada consulta descuenta tokens.</p>}
      </section>
      {aviso && <Aviso tono="alerta" alCerrar={() => setAviso('')}>{aviso}</Aviso>}

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {accesos.map(({ href, titulo, texto: t, icono: Icono }, i) => (
          <Link key={href} href={href} style={{ animationDelay: `${i * 50}ms` }}
            className="aparecer group rounded-xl border border-borde bg-white p-5 shadow-tarjeta transition hover:-translate-y-0.5 hover:border-azul-25">
            <span className="grid size-10 place-items-center rounded-lg bg-azul-10 text-azul transition group-hover:bg-azul group-hover:text-white"><Icono className="size-5" /></span>
            <p className="mt-4 flex items-center gap-2 font-semibold text-texto">{titulo}<ArrowRight className="size-4 text-rojo opacity-0 transition group-hover:translate-x-1 group-hover:opacity-100" /></p>
            <p className="mt-1 text-sm text-gris">{t}</p>
          </Link>
        ))}
      </section>
    </div>
  );
}
