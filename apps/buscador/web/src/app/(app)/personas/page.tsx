'use client';
import { useCallback, useEffect, useState } from 'react';
import { IdCard, Phone, UserRound, UserSearch } from 'lucide-react';
import { BarraBusqueda } from '@/modulos/consultas/barra-busqueda';
import { FichaReniec } from '@/modulos/personas/ficha-reniec';
import { Resumen, Seccion, SeccionesResultado, colMoviles } from '@/modulos/consultas/resultados';
import { useSesion } from '@/modulos/sesion/proveedor';
import { Aviso, Boton, Cargando, Encabezado, Pestanas, Tabla, Tarjeta, Vacio } from '@/components/ui';
import { ErrorApi } from '@/lib/api';
import { servicioPersonas } from '@/modulos/personas/servicio';
import { fNumero } from '@/lib/formato';
import type { ResultadoPersona, ResultadoReniec, ResultadoTelefono } from '@/modulos/personas/tipos';

type Modo = 'dni' | 'telefono' | 'nombres';

export default function Personas() {
  const { actualizarSaldo } = useSesion();
  const [modo, setModo] = useState<Modo>('dni');
  const [inicial, setInicial] = useState('');
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState('');
  const [persona, setPersona] = useState<ResultadoPersona | null>(null);
  const [reniec, setReniec] = useState<ResultadoReniec | null>(null);
  const [cargandoReniec, setCargandoReniec] = useState(false);
  const [telefono, setTelefono] = useState<ResultadoTelefono | null>(null);

  const limpiar = () => { setError(''); setPersona(null); setReniec(null); setTelefono(null); };

  const buscarDni = useCallback(async (dni: string) => {
    limpiar();
    setCargando(true);
    try {
      setPersona(await servicioPersonas.porDni(dni));
    } catch (e) {
      setError(e instanceof ErrorApi ? e.message : 'No se pudo realizar la consulta.');
    } finally {
      setCargando(false);
      actualizarSaldo();
    }
  }, [actualizarSaldo]);

  const buscarTelefono = useCallback(async (numero: string) => {
    limpiar();
    setCargando(true);
    try {
      setTelefono(await servicioPersonas.porTelefono(numero));
    } catch (e) {
      setError(e instanceof ErrorApi ? e.message : 'No se pudo realizar la consulta.');
    } finally {
      setCargando(false);
      actualizarSaldo();
    }
  }, [actualizarSaldo]);

  async function consultarReniec() {
    if (!persona) return;
    setCargandoReniec(true);
    try {
      setReniec(await servicioPersonas.reniec(persona.documento));
    } catch (e) {
      setError(e instanceof ErrorApi ? e.message : 'No se pudo consultar RENIEC.');
    } finally {
      setCargandoReniec(false);
      actualizarSaldo();
    }
  }

  // Busqueda que llega desde Inicio (?dni= o ?telefono=)
  useEffect(() => {
    const q = new URLSearchParams(location.search);
    const dni = q.get('dni'); const tel = q.get('telefono');
    if (dni) { setModo('dni'); setInicial(dni); buscarDni(dni); }
    else if (tel) { setModo('telefono'); setInicial(tel); buscarTelefono(tel); }
  }, [buscarDni, buscarTelefono]);

  return (
    <div className="space-y-6">
      <Encabezado titulo="Consulta de personas" bajada="Cada consulta descuenta tokens y queda registrada en la auditoría." />
      <Pestanas<Modo>
        valor={modo} alCambiar={(m) => { setModo(m); limpiar(); setInicial(''); }}
        opciones={[
          { id: 'dni', texto: 'DNI', icono: <IdCard className="size-4" /> },
          { id: 'telefono', texto: 'Teléfono', icono: <Phone className="size-4" /> },
          { id: 'nombres', texto: 'Apellidos y nombres', icono: <UserRound className="size-4" /> },
        ]}
      />

      <Tarjeta>
        {modo === 'dni' && (
          <BarraBusqueda key={`dni-${inicial}`} etiqueta="DNI" placeholder="DNI de 8 dígitos" valorInicial={inicial} cargando={cargando}
            validar={(v) => (/^\d{8}$/.test(v) ? null : 'El DNI debe tener 8 dígitos.')} alBuscar={buscarDni} />
        )}
        {modo === 'telefono' && (
          <BarraBusqueda key={`tel-${inicial}`} etiqueta="Teléfono" placeholder="Celular de 9 dígitos" valorInicial={inicial} cargando={cargando}
            validar={(v) => (/^\d{9}$/.test(v) ? null : 'El teléfono debe tener 9 dígitos.')} alBuscar={buscarTelefono} />
        )}
        {modo === 'nombres' && (
          <Vacio icono={<UserRound className="size-5" />} titulo="Búsqueda por apellidos y nombres: próximamente">
            Esta búsqueda aún no está disponible en el sistema. Mientras tanto, consulta por DNI o por teléfono.
          </Vacio>
        )}
      </Tarjeta>

      {error && <Aviso tono="error" alCerrar={() => setError('')}>{error}</Aviso>}
      {cargando && <Cargando />}

      {persona && (
        <div className="space-y-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h2 className="numeros text-lg font-semibold text-texto">DNI {persona.documento}</h2>
            {!reniec && <Boton variante="secundario" onClick={consultarReniec} cargando={cargandoReniec}><IdCard className="size-4" />Ver datos RENIEC</Boton>}
          </div>
          {!persona.esDniValido && <Aviso tono="alerta">El DNI no figura como válido en las fuentes consultadas.</Aviso>}
          {reniec && <FichaReniec r={reniec} />}
          <Resumen s={persona} />
          <SeccionesResultado s={persona} />
        </div>
      )}

      {telefono && (
        <Seccion titulo={`Teléfono ${telefono.telefono}`} icono={<Phone className="size-[18px]" />} cantidad={telefono.registros.length}>
          <p className="border-b border-borde px-5 py-2.5 text-sm text-gris">{fNumero(telefono.documentosAsociados)} documento(s) asociado(s)</p>
          <Tabla columnas={colMoviles} filas={telefono.registros} clave={(m, i) => `${m.documento}-${i}`} vacio="No se encontraron registros para este número." />
        </Seccion>
      )}

      {!cargando && !persona && !telefono && !error && modo !== 'nombres' && (
        <Vacio icono={<UserSearch className="size-5" />} titulo="Escribe un documento para empezar">
          Verás deudas, líneas de crédito, calificaciones, información laboral y teléfonos.
        </Vacio>
      )}
    </div>
  );
}
