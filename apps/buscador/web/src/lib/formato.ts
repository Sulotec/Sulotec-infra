// Formatos para Peru (es-PE).

const numero = new Intl.NumberFormat('es-PE');
const moneda = new Intl.NumberFormat('es-PE', { style: 'currency', currency: 'PEN', minimumFractionDigits: 2 });

export const fNumero = (n: number | null | undefined) => (n == null ? '—' : numero.format(n));
export const fMoneda = (n: number | null | undefined) => (n == null ? '—' : moneda.format(n));
export const fTexto = (t: string | null | undefined) => (t == null || String(t).trim() === '' ? '—' : String(t));

export function fFecha(valor: string | null | undefined, conHora = false): string {
  if (!valor) return '—';
  const d = new Date(valor);
  if (Number.isNaN(d.getTime())) return valor;
  return d.toLocaleString('es-PE', conHora
    ? { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }
    : { day: '2-digit', month: '2-digit', year: 'numeric' });
}

// Periodos SBS: "202609" -> "Set 2026"
const MESES = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Set', 'Oct', 'Nov', 'Dic'];
export function fPeriodo(p: string | null | undefined): string {
  if (!p) return '—';
  const m = String(p).match(/^(\d{4})(\d{2})$/);
  return m ? `${MESES[Number(m[2]) - 1] ?? m[2]} ${m[1]}` : String(p);
}

export function fBytes(b: number): string {
  if (b < 1024) return `${b} B`;
  if (b < 1024 * 1024) return `${(b / 1024).toFixed(1)} KB`;
  return `${(b / 1024 / 1024).toFixed(1)} MB`;
}

export const nombreCompleto = (...partes: (string | null | undefined)[]) =>
  partes.filter((p) => p && String(p).trim()).join(' ') || '—';
