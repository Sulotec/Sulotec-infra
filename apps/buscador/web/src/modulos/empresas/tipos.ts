// Tipos del modulo empresas (mismo contrato que la API del Buscador).
import type { Deuda, LineaCredito, Calificacion } from "@/modulos/consultas/tipos";

export interface ResultadoEmpresa {
  moviles: Record<string, unknown>[]; sueldos: Record<string, unknown>[];
  deudas: Deuda[]; lineasCredito: LineaCredito[]; calificaciones: Calificacion[];
}
