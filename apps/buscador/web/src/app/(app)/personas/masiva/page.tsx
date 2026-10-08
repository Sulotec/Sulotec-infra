'use client';
import { Encabezado } from '@/components/ui';
import { CargaMasiva } from '@/modulos/masiva/carga-masiva';

export default function PersonasMasiva() {
  return (
    <>
      <Encabezado titulo="Carga masiva de personas" bajada="Consulta hasta 10 000 documentos a la vez y descarga el resultado en Excel. Cada documento descuenta tokens." />
      <CargaMasiva tipo="personas" />
    </>
  );
}
