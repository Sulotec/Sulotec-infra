// Tipos del modulo consultas (mismo contrato que la API del Buscador).

export interface Deuda {
  periodo: string; codigoSbs: string | null; documento: string; razonSocial: string | null;
  codigoEmpresa?: string | null; entidad: string | null; tipoDeuda: string | null; dias: number | null;
  calificacion: string | null; saldo: number | null; fechaCarga?: string;
}

export interface LineaCredito {
  periodo: string | null; codigoSbs: string | null; documento: string | null; razonSocial: string | null;
  codigoEmpresa?: string | null; entidad: string | null; tipo: string | null; lineaCreditoMonto: number | null;
  lineaNoUtilizada: number | null; lineaUtilizada: number | null; fechaCarga?: string;
}

export interface Calificacion {
  periodo: string | null; codigoSbs: string | null; documento: string | null;
  nor: number | null; cpp: number | null; def: number | null; dud: number | null; per: number | null;
  reportan: string | null; apePat: string | null; apeMat: string | null; priNombre: string | null;
  segNombre: string | null; fechaCarga?: string;
}

export interface Sueldo {
  id?: number; periodo: string; tipoDoc?: string | null; documento: string | null; apeNom: string | null;
  ruc: string | null; empresa: string | null; genero?: string | null; montoSueldo: number | null;
  gratifBono: number | null; ingresoEstimadoAnual: number | null; codRangoSueldo?: string | null;
  rangoSueldo: string | null; segmentoSueldo: string | null; nivelIngreso: string | null; fechaCarga?: string;
}

export interface Movil {
  periodo: string | null; documento: string | null; apePat: string | null; apeMat: string | null;
  prenombres: string | null; telefono: string | null; fechaAlta: string | null; planMovil: string | null;
  modalidad: string | null; empresaOperadora: string | null; fechaCarga?: string;
}
