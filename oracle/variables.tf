variable "tenancy_ocid" {
  type        = string
  description = "OCID del tenancy (en Cloud Shell: echo $OCI_TENANCY)"
}

variable "compartment_ocid" {
  type        = string
  description = "OCID del compartment donde se crea todo. Si no creaste otro, usa el mismo del tenancy."
}

variable "region" {
  type        = string
  description = "Region HOME de tu cuenta (en Cloud Shell: echo $OCI_REGION). Ej: sa-santiago-1"
}

variable "ssh_public_key" {
  type        = string
  description = "Contenido de tu llave publica SSH (id_ed25519.pub)"
}

variable "admin_cidr" {
  type        = string
  description = "Tu IP publica con /32 (ej. 190.12.34.56/32). Es la unica que podra entrar por SSH."
}

variable "alert_email" {
  type        = string
  description = "Correo que recibe las alertas de presupuesto"
}

variable "budget_usd" {
  type        = number
  default     = 10
  description = "Presupuesto mensual en USD; alerta al 50%, 80% y 100% gastado"
}

variable "name" {
  type    = string
  default = "sulotec"
}

variable "ubuntu_version" {
  type    = string
  default = "24.04"
}

# Maximo de la capa Always Free: 4 OCPU / 24 GB en total (ARM Ampere A1)
variable "ocpus" {
  type    = number
  default = 4
}

variable "memory_gb" {
  type    = number
  default = 24
}

# Always Free incluye 200 GB de block storage en total (boot_gb + data_gb)
variable "boot_gb" {
  type    = number
  default = 150
}

variable "data_gb" {
  type        = number
  default     = 50
  description = "Disco de datos montado en /data (bases y archivos de las apps)"
}

variable "ssh_enabled" {
  type        = bool
  default     = true
  description = "true abre el puerto 22 solo a admin_cidr (emergencias). false = solo acceso por https://ssh.sulotec.com"
}
