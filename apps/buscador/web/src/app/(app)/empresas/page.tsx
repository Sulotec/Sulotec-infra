'use client';
import { useCallback, useEffect, useState } from 'react';
import { Building2, Hash } from 'lucide-react';
import { BarraBusqueda } from '@/modulos/consultas/barra-busqueda';
import { Resumen, SeccionesResultado } from '@/modulos/consultas/resultados';
import { useSesion } from '@/modulos/sesion/proveedor';
import { Aviso, Cargando, Encabezado, Pestanas, Tarjeta, Vacio } from '@/components/ui';
import { ErrorApi } from '@/lib/api';
import { servicioEmpresas } from '@/modulos/empresas/servicio';
import type { ResultadoEmpresa } from '@/modulos/empresas/tipos';

type Modo = 'ruc' | 'razon';

export default function Empresas() {
  const { actualizarSaldo } = useSesion();
  const [modo, setModo] = useState<Modo>('ruc');
  const [inicial, setInicial] = useState('');
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState('');
  const [consulta, setConsulta] = useState('');
  const [empresa, setEmpresa] = useState<ResultadoEmpresa | null>(null);
  const [sinDatos, setSinDatos] = useState(false);

  const buscar = useCallback(async (m: Modo, valor: string) => {
    setError(''); setEmpresa(null); setSinDatos(false); setCargando(true); setConsulta(valor);
    try {
      const r = m === 'ruc' ? await servicioEmpresas.porRuc(valor) : await servicioEmpresas.porRazonSocial(valor);
      if (!r) setSinDatos(true); else setEmpresa(r);
    } catch (e) {
      if (e instanceof ErrorApi && e.estado === 404) setSinDatos(true);
      else setError(e instanceof ErrorApi ? e.message : 'No se pudo realizar la consulta.');
    } finally {
      setCargando(false);
      actualizarSaldo();
    }
  }, [actualizarSaldo]);

  useEffect(() => {
    const ruc = new URLSearchParams(location.search).get('ruc');
    if (ruc) { setInicial(ruc); buscar('ruc', ruc); }
  }, [buscar]);

  const vacia = empresa && !empresa.deudas.length && !empresa.lineasCredito.length && !empresa.calificaciones.length && !empresa.sueldos.length && !empresa.moviles.length;

  return (
    <div className="space-y-6">
      <Encabezado titulo="Consulta de empresas" bajada="Busca por RUC o por razón social. Cada consulta queda registrada en la auditoría." />
      <Pestanas<Modo> valor={modo} alCambiar={(m) => { setModo(m); setEmpresa(null); setError(''); setSinDatos(false); setInicial(''); }}
        opciones={[{ id: 'ruc', texto: 'RUC', icono: <Hash className="size-4" /> }, { id: 'razon', texto: 'Razón social', icono: <Building2 className="size-4" /> }]} />

      <Tarjeta>
        {modo === 'ruc' ? (
          <BarraBusqueda key={`ruc-${inicial}`} etiqueta="RUC" placeholder="RUC de 11 dígitos" valorInicial={inicial} cargando={cargando}
            validar={(v) => (/^(10|15|16|17|20)\d{9}$/.test(v) ? null : 'El RUC debe tener 11 dígitos y empezar con 10, 15, 16, 17 o 20.')}
            alBuscar={(v) => buscar('ruc', v)} />
        ) : (
          <BarraBusqueda key="razon" etiqueta="Razón social" placeholder="Nombre de la empresa" numerica={false} cargando={cargando}
            validar={(v) => (v.length >= 3 ? null : 'Escribe al menos 3 letras.')} alBuscar={(v) => buscar('razon', v)} />
        )}
      </Tarjeta>

      {error && <Aviso tono="error" alCerrar={() => setError('')}>{error}</Aviso>}
      {cargando && <Cargando />}
      {sinDatos && <Vacio icono={<Building2 className="size-5" />} titulo="Sin resultados">No encontramos información para «{consulta}».</Vacio>}
      {empresa && (vacia
        ? <Vacio icono={<Building2 className="size-5" />} titulo="Sin información registrada">La empresa «{consulta}» no tiene registros en las fuentes consultadas.</Vacio>
        : (
          <div className="space-y-4">
            <h2 className="numeros text-lg font-semibold text-texto">{modo === 'ruc' ? `RUC ${consulta}` : consulta}</h2>
            <Resumen s={empresa} />
            <SeccionesResultado s={empresa} tipadas={false} />
          </div>
        ))}
      {!cargando && !empresa && !sinDatos && !error && (
        <Vacio icono={<Building2 className="size-5" />} titulo="Escribe un RUC o una razón social">Verás deudas, líneas de crédito, calificaciones, trabajadores y teléfonos.</Vacio>
      )}
    </div>
  );
}
