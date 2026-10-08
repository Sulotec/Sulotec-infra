'use client';
// Muestra su contenido solo al rol ADMIN GENERAL (la API valida lo mismo en cada llamada).
import { ShieldAlert } from 'lucide-react';
import type { ReactNode } from 'react';
import { Vacio } from '@/components/ui';
import { useSesion } from '@/modulos/sesion/proveedor';

export function SoloAdmin({ children }: { children: ReactNode }) {
  const { esAdmin } = useSesion();
  if (!esAdmin) {
    return <Vacio icono={<ShieldAlert className="size-5" />} titulo="Sección solo para Administradores Generales">Si necesitas acceso, pídeselo a un Administrador General.</Vacio>;
  }
  return <>{children}</>;
}
