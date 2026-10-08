'use client';
import { SoloAdmin } from '@/modulos/admin/solo-admin';
import { AdminUsuarios } from '@/modulos/admin/usuarios';

export default function PaginaUsuarios() {
  return <SoloAdmin><AdminUsuarios /></SoloAdmin>;
}
