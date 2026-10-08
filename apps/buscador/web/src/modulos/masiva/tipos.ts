// Tipos del modulo masiva (mismo contrato que la API del Buscador).

export interface HistorialDescarga {
  id: number; archivo: string; secciones: string[]; totalDnis: number; tamanoBytes: number; fecha: string;
  dnisConResultados?: number | null; dnisSinResultados?: number | null; duracionSegundos?: number | null;
  estado?: string | null;
}
