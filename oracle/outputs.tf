output "public_ip" {
  value = oci_core_instance.main.public_ip
}

output "ssh" {
  value = "ssh ubuntu@${oci_core_instance.main.public_ip}"
}

output "backup_bucket" {
  value = local.bucket_name
}

output "archivos_bucket" {
  value = oci_objectstorage_bucket.archivos.name
}

output "object_storage_namespace" {
  value = data.oci_objectstorage_namespace.ns.namespace
}
