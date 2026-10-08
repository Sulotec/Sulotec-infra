'use client';
import { ProveedorSesion } from '@/modulos/sesion/proveedor';
import { Shell } from '@/components/layout/shell';

export default function LayoutAplicacion({ children }: { children: React.ReactNode }) {
  return (
    <ProveedorSesion>
      <Shell>{children}</Shell>
    </ProveedorSesion>
  );
}
