// Logo de Sulotec + nombre del producto.
export function Marca({ claro = true }: { claro?: boolean }) {
  return (
    <span className="flex items-center gap-2.5">
      <svg viewBox="0 0 64 64" className="size-8 shrink-0" aria-hidden>
        <rect width="64" height="64" rx="16" fill={claro ? '#fff' : '#1b4589'} />
        <path d="M42 22c-2-3-6-5-10-5-6 0-10 3-10 8 0 11 20 6 20 16 0 5-4 8-10 8-5 0-9-2-11-6" fill="none" stroke={claro ? '#1b4589' : '#fff'} strokeWidth="5.5" strokeLinecap="round" />
        <circle cx="50" cy="50" r="4.5" fill="#ed1c24" />
      </svg>
      <span className="leading-tight">
        <span className={claro ? 'block text-[15px] font-bold text-white' : 'block text-[15px] font-bold text-azul'}>Buscador Interno</span>
        <span className={claro ? 'block text-[11px] text-azul-50' : 'block text-[11px] text-gris'}>Sulotec</span>
      </span>
    </span>
  );
}
