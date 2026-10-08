'use client';
// Formularios de administracion: crear usuario, cambiar roles y asignar tokens.
import clsx from 'clsx';
import { useEffect, useState, type FormEvent } from 'react';
import { Aviso, Boton, Campo, Tabla, type Columna } from '@/components/ui';
import { ErrorApi } from '@/lib/api';
import { fFecha, fNumero } from '@/lib/formato';
import { servicioAdmin } from './servicio';
import type { MovimientoToken, RolListado, UsuarioListado } from './tipos';

const mensaje = (e: unknown, porDefecto: string) => (e instanceof ErrorApi ? e.message : porDefecto);

function SelectorRoles({ roles, elegidos, alCambiar }: { roles: RolListado[]; elegidos: number[]; alCambiar: (r: number[]) => void }) {
  return (
    <div className="grid gap-2 sm:grid-cols-2">
      {roles.map((r) => {
        const marcado = elegidos.includes(r.codigoRol);
        return (
          <label key={r.codigoRol} className={clsx('flex cursor-pointer gap-3 rounded-lg border p-3', marcado ? 'border-azul bg-azul-10/60' : 'border-borde hover:border-azul-25')}>
            <input type="checkbox" className="mt-0.5 size-4 accent-[var(--color-azul)]" checked={marcado}
              onChange={() => alCambiar(marcado ? elegidos.filter((x) => x !== r.codigoRol) : [...elegidos, r.codigoRol])} />
            <span><span className="block text-sm font-semibold">{r.rol}</span>{r.descripcion && <span className="block text-xs text-gris">{r.descripcion}</span>}</span>
          </label>
        );
      })}
    </div>
  );
}

export function FormularioCrear({ roles, alTerminar }: { roles: RolListado[]; alTerminar: (mensaje: string) => void }) {
  const [d, setD] = useState({ nombres: '', apePat: '', apeMat: '', usuarioLogin: '', correo: '', dni: '', telefono: '', tokensIniciales: '0' });
  const [codRoles, setCodRoles] = useState<number[]>([]);
  const [error, setError] = useState('');
  const [cargando, setCargando] = useState(false);
  const campo = (k: keyof typeof d) => ({ name: k, value: d[k], onChange: (e: React.ChangeEvent<HTMLInputElement>) => setD({ ...d, [k]: e.target.value }) });

  async function guardar(e: FormEvent) {
    e.preventDefault();
    if (!d.nombres.trim() || !d.apePat.trim() || !d.usuarioLogin.trim() || !d.correo.trim()) { setError('Completa nombres, apellido paterno, usuario y correo.'); return; }
    if (!codRoles.length) { setError('Elige al menos un rol.'); return; }
    setCargando(true); setError('');
    try {
      const r = await servicioAdmin.crear({
        nombres: d.nombres.trim(), apePat: d.apePat.trim(), apeMat: d.apeMat.trim() || null, usuarioLogin: d.usuarioLogin.trim(),
        correo: d.correo.trim(), dni: d.dni.trim() || null, telefono: d.telefono.trim() || null, codRoles,
        tokensIniciales: Math.max(0, Number(d.tokensIniciales) || 0),
      });
      alTerminar(r.invitacionEnviada
        ? `Se creó ${r.usuarioLogin} y se le envió la invitación por correo.`
        : `Se creó ${r.usuarioLogin}. No se pudo enviar el correo de invitación: el sistema aún no tiene correo configurado.`);
    } catch (err) {
      setError(mensaje(err, 'No se pudo crear el usuario.'));
    } finally {
      setCargando(false);
    }
  }

  return (
    <form onSubmit={guardar} className="space-y-4" noValidate>
      {error && <Aviso tono="error">{error}</Aviso>}
      <div className="grid gap-3 sm:grid-cols-3">
        <Campo etiqueta="Nombres" {...campo('nombres')} />
        <Campo etiqueta="Apellido paterno" {...campo('apePat')} />
        <Campo etiqueta="Apellido materno" {...campo('apeMat')} />
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <Campo etiqueta="Usuario" ayuda="Con este nombre inicia sesión." {...campo('usuarioLogin')} />
        <Campo etiqueta="Correo" type="email" ayuda="Aquí llega la invitación." {...campo('correo')} />
        <Campo etiqueta="DNI (opcional)" inputMode="numeric" {...campo('dni')} />
        <Campo etiqueta="Teléfono (opcional)" inputMode="tel" {...campo('telefono')} />
      </div>
      <div>
        <p className="mb-2 text-sm font-medium">Roles</p>
        <SelectorRoles roles={roles} elegidos={codRoles} alCambiar={setCodRoles} />
      </div>
      <Campo etiqueta="Tokens iniciales" type="number" min={0} className="max-w-48" {...campo('tokensIniciales')} />
      <div className="flex justify-end"><Boton type="submit" cargando={cargando}>Crear usuario</Boton></div>
    </form>
  );
}

export function FormularioRoles({ usuario, roles, alTerminar }: { usuario: UsuarioListado; roles: RolListado[]; alTerminar: (mensaje: string) => void }) {
  const [elegidos, setElegidos] = useState(roles.filter((r) => usuario.roles.some((x) => x.toUpperCase() === r.rol.toUpperCase())).map((r) => r.codigoRol));
  const [error, setError] = useState('');
  const [cargando, setCargando] = useState(false);

  async function guardar() {
    if (!elegidos.length) { setError('Elige al menos un rol.'); return; }
    setCargando(true); setError('');
    try { await servicioAdmin.cambiarRoles(usuario.id, elegidos); alTerminar(`Se actualizaron los roles de ${usuario.usuario}.`); }
    catch (err) { setError(mensaje(err, 'No se pudieron guardar los roles.')); }
    finally { setCargando(false); }
  }

  return (
    <div className="space-y-4">
      {error && <Aviso tono="error">{error}</Aviso>}
      <SelectorRoles roles={roles} elegidos={elegidos} alCambiar={setElegidos} />
      <div className="flex justify-end"><Boton onClick={guardar} cargando={cargando}>Guardar roles</Boton></div>
    </div>
  );
}

export function FormularioTokens({ usuario, alTerminar }: { usuario: UsuarioListado; alTerminar: (mensaje: string) => void }) {
  const [cantidad, setCantidad] = useState('');
  const [motivo, setMotivo] = useState('');
  const [error, setError] = useState('');
  const [cargando, setCargando] = useState(false);
  const [movimientos, setMovimientos] = useState<MovimientoToken[] | null>(null);

  useEffect(() => { servicioAdmin.movimientos(usuario.id).then(setMovimientos).catch(() => setMovimientos([])); }, [usuario.id]);

  async function asignar(e: FormEvent) {
    e.preventDefault();
    const n = Number(cantidad);
    if (!Number.isInteger(n) || n === 0) { setError('Escribe una cantidad entera (negativa para descontar).'); return; }
    if (motivo.trim().length < 3) { setError('Escribe el motivo.'); return; }
    setCargando(true); setError('');
    try {
      const s = await servicioAdmin.asignarTokens(usuario.id, n, motivo.trim());
      alTerminar(`${usuario.usuario} ahora tiene ${fNumero(s.saldo)} tokens.`);
    } catch (err) { setError(mensaje(err, 'No se pudieron asignar los tokens.')); }
    finally { setCargando(false); }
  }

  const columnas: Columna<MovimientoToken>[] = [
    { titulo: 'Fecha', celda: (m) => fFecha(m.fecha, true) },
    { titulo: 'Acción', celda: (m) => m.accion },
    { titulo: 'Cantidad', celda: (m) => <span className={m.cantidad < 0 ? 'text-peligro' : 'text-verde'}>{m.cantidad > 0 ? '+' : ''}{fNumero(m.cantidad)}</span>, derecha: true },
    { titulo: 'Saldo', celda: (m) => fNumero(m.saldoResultante), derecha: true },
    { titulo: 'Detalle', celda: (m) => m.detalle ?? '—' },
  ];

  return (
    <div className="space-y-5">
      <p className="text-sm text-gris">Saldo actual: <strong className="numeros text-texto">{fNumero(usuario.saldoTokens)} tokens</strong></p>
      <form onSubmit={asignar} className="grid gap-3 sm:grid-cols-[10rem_1fr_auto] sm:items-end" noValidate>
        <Campo etiqueta="Cantidad" type="number" value={cantidad} onChange={(e) => setCantidad(e.target.value)} placeholder="Ej. 100" />
        <Campo etiqueta="Motivo" value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Ej. Recarga mensual" />
        <Boton type="submit" cargando={cargando}>Asignar</Boton>
      </form>
      {error && <Aviso tono="error">{error}</Aviso>}
      <div className="overflow-hidden rounded-lg border border-borde">
        {movimientos === null ? <p className="p-4 text-sm text-gris">Cargando movimientos…</p>
          : <Tabla columnas={columnas} filas={movimientos} clave={(m) => m.codMovimiento} vacio="Sin movimientos." />}
      </div>
    </div>
  );
}
