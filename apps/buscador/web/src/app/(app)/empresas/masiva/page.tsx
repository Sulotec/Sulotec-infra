'use client';
import { Encabezado } from '@/components/ui';
import { CargaMasiva } from '@/modulos/masiva/carga-masiva';

export default function EmpresasMasiva() {
  return (
    <>
      <Encabezado titulo="Carga masiva de empresas" bajada="Consulta muchos RUC a la vez y descarga el resultado en Excel. Cada RUC descuenta tokens." />
      <CargaMasiva tipo="empresas" />
    </>
  );
}
