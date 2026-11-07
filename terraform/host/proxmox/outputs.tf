output "image_datastore_id" {
  description = "Id of the image datastore."
  value       = proxmox_storage_directory.images.id
}
