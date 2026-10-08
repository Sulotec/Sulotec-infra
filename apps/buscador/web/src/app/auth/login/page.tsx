'use client';
import Link from 'next/link';
import { useState, type FormEvent } from 'react';
import { MarcoAcceso } from '@/components/layout/acceso';
import { Aviso, Boton, Campo } from '@/components/ui';
import { ErrorApi } from '@/lib/api';
import { servicioSesion } from '@/modulos/sesion/servicio';

export default function PaginaLogin() {
  const [usuario, setUsuario] = useState('');
  const [clave, setClave] = useState('');
  const [error, setError] = useState('');
  const [cargando, setCargando] = useState(false);

  async function entrar(e: FormEvent) {
    e.preventDefault();
    if (!usuario.trim() || !clave) { setError('Escribe tu usuario y tu contraseña.'); return; }
    setCargando(true);
    setError('');
    try {
      await servicioSesion.iniciar(usuario.trim(), clave);
      const volver = new URLSearchParams(location.search).get('volver');
      location.replace(volver && volver.startsWith('/') && !volver.startsWith('//') ? volver : '/inicio');
    } catch (err) {
      setError(err instanceof ErrorApi && err.estado !== 401 ? err.message : 'Usuario o contraseña incorrectos.');
      setCargando(false);
    }
  }

  return (
    <MarcoAcceso titulo="Iniciar sesión" bajada="Ingresa con tu cuenta del Buscador Interno.">
      <form onSubmit={entrar} className="space-y-4" noValidate>
        {error && <Aviso tono="error">{error}</Aviso>}
        <Campo etiqueta="Usuario" name="usuario" autoComplete="username" value={usuario} onChange={(e) => setUsuario(e.target.value)} autoFocus />
        <Campo etiqueta="Contraseña" name="clave" type="password" autoComplete="current-password" value={clave} onChange={(e) => setClave(e.target.value)} />
        <Boton type="submit" cargando={cargando} className="w-full h-11">Iniciar sesión</Boton>
        <p className="text-center text-sm"><Link href="/auth/forgot-password" className="font-semibold text-azul hover:underline">¿Olvidaste tu contraseña?</Link></p>
      </form>
    </MarcoAcceso>
  );
}
