'use client';
import Link from 'next/link';
import { useState, type FormEvent } from 'react';
import { MarcoAcceso } from '@/components/layout/acceso';
import { Aviso, Boton, Campo } from '@/components/ui';
import { ErrorApi } from '@/lib/api';
import { servicioSesion } from '@/modulos/sesion/servicio';

export default function PaginaOlvide() {
  const [identificador, setIdentificador] = useState('');
  const [mensaje, setMensaje] = useState('');
  const [error, setError] = useState('');
  const [cargando, setCargando] = useState(false);

  async function enviar(e: FormEvent) {
    e.preventDefault();
    if (!identificador.trim()) { setError('Escribe tu usuario o tu correo.'); return; }
    setCargando(true);
    setError('');
    try {
      const r = await servicioSesion.olvide(identificador.trim());
      setMensaje(r?.message || 'Si los datos son correctos, te enviamos un correo con el enlace para crear una nueva contraseña.');
    } catch (err) {
      setError(err instanceof ErrorApi ? err.message : 'No se pudo enviar el correo.');
    } finally {
      setCargando(false);
    }
  }

  return (
    <MarcoAcceso titulo="Recuperar contraseña" bajada="Te enviaremos un enlace a tu correo para crear una nueva contraseña.">
      {mensaje ? (
        <div className="space-y-6"><Aviso tono="exito">{mensaje}</Aviso><Link href="/auth/login" className="text-sm font-semibold text-azul hover:underline">Volver a iniciar sesión</Link></div>
      ) : (
        <form onSubmit={enviar} className="space-y-4" noValidate>
          {error && <Aviso tono="error">{error}</Aviso>}
          <Campo etiqueta="Usuario o correo" name="identificador" value={identificador} onChange={(e) => setIdentificador(e.target.value)} autoFocus />
          <Boton type="submit" cargando={cargando} className="w-full h-11">Enviar enlace</Boton>
          <p className="text-center text-sm"><Link href="/auth/login" className="font-semibold text-azul hover:underline">Volver a iniciar sesión</Link></p>
        </form>
      )}
    </MarcoAcceso>
  );
}
