// Servicio de carga masiva: procesa una lista de documentos y devuelve un Excel; historial de descargas.
import { api, descargar, subirYDescargar, type Archivo } from '@/lib/api';
import type { TipoLista } from './documentos';
import type { HistorialDescarga } from './tipos';

const RUTA_EXPORTAR: Record<TipoLista, string> = {
  personas: 'api/buscador/masivo/exportar',
  empresas: 'api/empresa/masivo/exportar',
};

export const servicioMasiva = {
  procesar(tipo: TipoLista, archivo: File, secciones: string[], alProgresar: (p: number) => void): Promise<Archivo> {
    const datos = new FormData();
    datos.append('archivo', archivo, archivo.name);
    secciones.forEach((s) => datos.append('secciones', s));
    return subirYDescargar(RUTA_EXPORTAR[tipo], datos, alProgresar, tipo === 'empresas' ? 'Resultado_Empresas.xlsx' : 'Resultado_Masivo.xlsx');
  },
  // La API actual guarda el historial con una segunda llamada (en la fase 2 lo hara sola al procesar).
  guardarEnHistorial(resultado: Archivo, secciones: string[], total: number) {
    const datos = new FormData();
    datos.append('archivoExcel', resultado.blob, resultado.nombre);
    secciones.forEach((s) => datos.append('secciones', s));
    datos.append('totalDnis', String(total));
    return api.post<{ mensaje: string }>('api/historial/masivo/historial', datos);
  },
  historial: (codUsuario: number) => api.get<HistorialDescarga[]>(`api/historial/usuario/${codUsuario}`),
  descargar: (h: HistorialDescarga) => descargar(`api/historial/${h.id}/descargar`, h.archivo),
};
