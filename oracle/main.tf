terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

# En Cloud Shell / Resource Manager la autenticacion es automatica.
provider "oci" {
  region = var.region
}

locals {
  bucket_name = "${var.name}-backups"
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = var.ubuntu_version
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# ---------- Red ----------

resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.name}-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = var.name
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.name}-igw"
  enabled        = true
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.name}-public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

# Web/HTTPS NO se abre: el trafico entra por Cloudflare Tunnel.
# SSH directo (puerto 22) solo si ssh_enabled = true y solo desde admin_cidr.
# El acceso normal es https://ssh.sulotec.com (Cloudflare Access), que no usa este puerto.
resource "oci_core_security_list" "ssh_only" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.name}-ssh-only"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  dynamic "ingress_security_rules" {
    for_each = var.ssh_enabled ? [1] : []
    content {
      protocol = "6"
      source   = var.admin_cidr

      tcp_options {
        min = 22
        max = 22
      }
    }
  }

  ingress_security_rules {
    protocol = "1"
    source   = "0.0.0.0/0"

    icmp_options {
      type = 3
      code = 4
    }
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  display_name               = "${var.name}-public"
  cidr_block                 = "10.0.1.0/24"
  dns_label                  = "pub"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.ssh_only.id]
  prohibit_public_ip_on_vnic = false
}

# ---------- Servidor ----------

resource "oci_core_instance" "main" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "${var.name}-main"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_gb
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = var.boot_gb
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(file("${path.module}/cloud-init.yaml"))
  }

  lifecycle {
    # evita recrear la VM cuando Oracle publica una imagen nueva.
    # metadata: Oracle no permite cambiar ssh_authorized_keys/user_data despues de crearla;
    # las llaves nuevas se agregan en ~/.ssh/authorized_keys dentro de la VM.
    ignore_changes = [source_details[0].source_id, metadata]
  }
}

# ---------- Disco de datos: bases y archivos de las apps, separado del sistema ----------
# Se monta en /data dentro de la VM. Boot (150) + datos (50) = 200 GB, el maximo de Always Free.
# Si algun dia se reemplaza la VM, este disco se conecta a la nueva con los datos intactos.

resource "oci_core_volume" "data" {
  compartment_id      = var.compartment_ocid
  availability_domain = oci_core_instance.main.availability_domain
  display_name        = "${var.name}-data"
  size_in_gbs         = var.data_gb
}

resource "oci_core_volume_attachment" "data" {
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.main.id
  volume_id       = oci_core_volume.data.id
  display_name    = "${var.name}-data"
}

# ---------- Archivos de las apps (fotos, documentos): Object Storage, API compatible S3 ----------

resource "oci_objectstorage_bucket" "archivos" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = "${var.name}-archivos"
  access_type    = "NoPublicAccess"
}

# ---------- Backups: bucket privado + permiso solo para esta VM ----------

resource "oci_objectstorage_bucket" "backups" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = local.bucket_name
  access_type    = "NoPublicAccess"
  versioning     = "Enabled"
}

resource "oci_identity_dynamic_group" "vm" {
  compartment_id = var.tenancy_ocid
  name           = "${var.name}-vm"
  description    = "VM principal de ${var.name}"
  matching_rule  = "instance.id = '${oci_core_instance.main.id}'"
}

resource "oci_identity_policy" "vm_backups" {
  compartment_id = var.tenancy_ocid
  name           = "${var.name}-vm-backups"
  description    = "La VM puede escribir backups en su bucket"
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.vm.name} to manage objects in compartment id ${var.compartment_ocid} where target.bucket.name = '${local.bucket_name}'",
    "Allow dynamic-group ${oci_identity_dynamic_group.vm.name} to read buckets in compartment id ${var.compartment_ocid}",
  ]
}

# ---------- Alertas de costo ----------

resource "oci_budget_budget" "monthly" {
  compartment_id = var.tenancy_ocid
  display_name   = "${var.name}-mensual"
  amount         = var.budget_usd
  reset_period   = "MONTHLY"
  target_type    = "COMPARTMENT"
  targets        = [var.compartment_ocid]
}

resource "oci_budget_alert_rule" "thresholds" {
  for_each       = toset(["50", "80", "100"])
  budget_id      = oci_budget_budget.monthly.id
  display_name   = "${each.key}-por-ciento"
  threshold      = tonumber(each.key)
  threshold_type = "PERCENTAGE"
  type           = "ACTUAL"
  recipients     = var.alert_email
  message        = "Se gasto el ${each.key}% del presupuesto mensual de Oracle Cloud (${var.name})."
}
