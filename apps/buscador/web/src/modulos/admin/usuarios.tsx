'use client';
// Administracion de usuarios: busqueda, alta, estado, roles, tokens y cierre de sesiones.
import { Coins, KeyRound, LogOut, Search, ShieldCheck, UserPlus } from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';
import { Aviso, Boton, Chip, Encabezado, Modal, Paginacion, Tabla, Tarjeta, type Columna } from '@/components/ui';
import { ErrorApi } from '@/lib/api';
import { fNumero } from '@/lib/formato';
import { FormularioCrear, FormularioRoles, FormularioTokens } from './formularios';
import { servicioAdmin } from './servicio';
import type { Pagina, RolListado, UsuarioListado } from './tipos';

const TAMANO = 15;
type Dialogo = { tipo: 'crear' } | { tipo: 'roles' | 'tokens'; usuario: UsuarioListado } | null;

export function AdminUsuarios() {
  const [texto, setTexto] = useState('');
  const [busqueda, setBusqueda] = useState('');
  const [pagina, setPagina] = useState(1);
  const [datos, setDatos] = useState<Pagina<UsuarioListado> | null>(null);
  const [roles, setRoles] = useState<RolListado[]>([]);
  const [dialogo, setDialogo] = useState<Dialogo>(null);
  const [aviso, setAviso] = useState<{ tono: 'exito' | 'error'; texto: string } | null>(null);
  const [ocupado, setOcupado] = useState<number | null>(null);

  const cargar = useCallback(() => {
    servicioAdmin.usuarios(busqueda, pagina, TAMANO).then(setDatos)
      .catch((e) => setAviso({ tono: 'error', texto: e instanceof ErrorApi ? e.message : 'No se pudo cargar la lista.' }));
  }, [busqueda, pagina]);
  useEffect(cargar, [cargar]);
  useEffect(() => { servicioAdmin.roles().then(setRoles).catch(() => setRoles([])); }, []);

  function terminar(texto: string) { setDialogo(null); setAviso({ tono: 'exito', texto }); cargar(); }

  async function accion(u: UsuarioListado, hacer: () => Promise<void>, exito: string) {
    setOcupado(u.id);
    try { await hacer(); setAviso({ tono: 'exito', texto: exito }); cargar(); }
    catch (e) { setAviso({ tono: 'error', texto: e instanceof ErrorApi ? e.message : 'No se pudo completar la acción.' }); }
    finally { setOcupado(null); }
  }

  const columnas: Columna<UsuarioListado>[] = [
    { titulo: 'Usuario', celda: (u) => <span><span className="block font-semibold">{u.nombreCompleto}</span><span className="block text-xs text-gris">{u.usuario}{u.correo ? ` · ${u.correo}` : ''}</span></span> },
    { titulo: 'Roles', celda: (u) => <div className="flex flex-wrap gap-1">{u.roles.map((r) => <Chip key={r} tono={r.toUpperCase() === 'ADMIN GENERAL' ? 'peligro' : 'azul'}>{r}</Chip>)}</div> },
    { titulo: 'Tokens', celda: (u) => fNumero(u.saldoTokens), derecha: true },
    { titulo: 'Estado', celda: (u) => <Chip tono={u.estado === 1 ? 'verde' : 'neutro'}>{u.estado === 1 ? 'Activo' : 'Inactivo'}</Chip> },
    {
      titulo: 'Acciones', derecha: true,
      celda: (u) => (
        <div className="flex justify-end gap-1">
          <Boton variante="fantasma" className="h-8 px-2" title="Roles" aria-label={`Roles de ${u.usuario}`} onClick={() => setDialogo({ tipo: 'roles', usuario: u })}><ShieldCheck className="size-4" /></Boton>
          <Boton variante="fantasma" className="h-8 px-2" title="Tokens" aria-label={`Tokens de ${u.usuario}`} onClick={() => setDialogo({ tipo: 'tokens', usuario: u })}><Coins className="size-4" /></Boton>
          <Boton variante="fantasma" className="h-8 px-2" title="Cerrar sus sesiones" aria-label={`Cerrar sesiones de ${u.usuario}`} cargando={ocupado === u.id}
            onClick={() => accion(u, () => servicioAdmin.cerrarSesiones(u.id), `Se cerraron las sesiones de ${u.usuario}.`)}><LogOut className="size-4" /></Boton>
          <Boton variante={u.estado === 1 ? 'peligro' : 'secundario'} className="h-8 px-3 text-xs"
            onClick={() => accion(u, () => servicioAdmin.cambiarEstado(u.id, u.estado !== 1), u.estado === 1 ? `${u.usuario} quedó inactivo.` : `${u.usuario} quedó activo.`)}>
            {u.estado === 1 ? 'Desactivar' : 'Activar'}
          </Boton>
        </div>
      ),
    },
  ];

  return (
    <>
      <Encabezado titulo="Usuarios y tokens" bajada="Crea cuentas, asigna roles y recarga tokens. Todo queda en la auditoría."
        accion={<Boton onClick={() => setDialogo({ tipo: 'crear' })}><UserPlus className="size-4" />Nuevo usuario</Boton>} />
      {aviso && <div className="mb-4"><Aviso tono={aviso.tono} alCerrar={() => setAviso(null)}>{aviso.texto}</Aviso></div>}
      <Tarjeta sinRelleno titulo={
        <form className="relative w-full max-w-sm" onSubmit={(e) => { e.preventDefault(); setPagina(1); setBusqueda(texto); }}>
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-gris" />
          <input value={texto} onChange={(e) => setTexto(e.target.value)} placeholder="Buscar por nombre, usuario o correo"
            className="h-9 w-full rounded-lg border border-borde bg-white pl-9 pr-3 text-sm focus:border-azul focus:outline-none" />
        </form>}>
        {datos ? <>
          <Tabla columnas={columnas} filas={datos.items} clave={(u) => u.id} vacio="No hay usuarios con esa búsqueda." />
          <Paginacion pagina={pagina} tamano={TAMANO} total={datos.total} alCambiar={setPagina} />
        </> : <p className="px-5 py-8 text-center text-sm text-gris">Cargando usuarios…</p>}
      </Tarjeta>

      <Modal abierto={dialogo?.tipo === 'crear'} titulo="Nuevo usuario" alCerrar={() => setDialogo(null)} ancho="max-w-2xl">
        <FormularioCrear roles={roles} alTerminar={terminar} />
      </Modal>
      <Modal abierto={dialogo?.tipo === 'roles'} titulo={dialogo?.tipo === 'roles' ? `Roles de ${dialogo.usuario.usuario}` : ''} alCerrar={() => setDialogo(null)}>
        {dialogo?.tipo === 'roles' && <FormularioRoles usuario={dialogo.usuario} roles={roles} alTerminar={terminar} />}
      </Modal>
      <Modal abierto={dialogo?.tipo === 'tokens'} titulo={dialogo?.tipo === 'tokens' ? `Tokens de ${dialogo.usuario.usuario}` : ''} alCerrar={() => setDialogo(null)} ancho="max-w-2xl">
        {dialogo?.tipo === 'tokens' && <FormularioTokens usuario={dialogo.usuario} alTerminar={terminar} />}
      </Modal>
      <p className="mt-4 flex items-center gap-2 text-xs text-gris"><KeyRound className="size-3.5" />Las contraseñas nunca se ven aquí: cada persona crea la suya con el enlace que recibe por correo.</p>
    </>
  );
}
