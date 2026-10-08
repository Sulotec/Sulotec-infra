'use client';
// El enlace de los correos de invitacion y recuperacion llega aqui: /auth/reset-password?token=...
import Link from 'next/link';
import { useState, type FormEvent } from 'react';
import { MarcoAcceso } from '@/components/layout/acceso';
import { Aviso, Boton, Campo } from '@/components/ui';
import { ErrorApi } from '@/lib/api';
import { servicioSesion } from '@/modulos/sesion/servicio';

export default function PaginaRestablecer() {
  const [clave, setClave] = useState('');
  const [repetir, setRepetir] = useState('');
  const [error, setError] = useState('');
  const [listo, setListo] = useState('');
  const [cargando, setCargando] = useState(false);

  async function guardar(e: FormEvent) {
    e.preventDefault();
    const token = new URLSearchParams(location.search).get('token');
    if (!token) { setError('El enlace no es válido. Pide uno nuevo.'); return; }
    if (clave.length < 8) { setError('La contraseña debe tener al menos 8 caracteres.'); return; }
    if (clave !== repetir) { setError('Las contraseñas no coinciden.'); return; }
    setCargando(true);
    setError('');
    try {
      const r = await servicioSesion.restablecer(token, clave);
      setListo(r?.message || 'Tu contraseña se guardó. Ya puedes iniciar sesión.');
    } catch (err) {
      setError(err instanceof ErrorApi ? err.message : 'No se pudo guardar la contraseña.');
    } finally {
      setCargando(false);
    }
  }

  return (
    <MarcoAcceso titulo="Crea tu contraseña" bajada="Elige una contraseña segura que no uses en otros sitios.">
      {listo ? (
        <div className="space-y-6"><Aviso tono="exito">{listo}</Aviso><Link href="/auth/login" className="text-sm font-semibold text-azul hover:underline">Iniciar sesión</Link></div>
      ) : (
        <form onSubmit={guardar} className="space-y-4" noValidate>
          {error && <Aviso tono="error">{error}</Aviso>}
          <Campo etiqueta="Nueva contraseña" name="clave" type="password" autoComplete="new-password" value={clave} onChange={(e) => setClave(e.target.value)} autoFocus />
          <Campo etiqueta="Repite la contraseña" name="repetir" type="password" autoComplete="new-password" value={repetir} onChange={(e) => setRepetir(e.target.value)} />
          <Boton type="submit" cargando={cargando} className="w-full h-11">Guardar contraseña</Boton>
        </form>
      )}
    </MarcoAcceso>
  );
}
