# -----------------------------------------------------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------------------------------------------------

variable "nodes" {
  description = "Proxmox VE nodes where the image datastore is available."
  type        = list(string)

  validation {
    condition     = length(var.nodes) > 0 && alltrue([for n in var.nodes : n != ""])
    error_message = "nodes must hold at least one non-empty node name."
  }
}

variable "image_datastore_id" {
  description = "Id of the directory storage that receives downloaded images."
  type        = string

  validation {
    condition     = var.image_datastore_id != ""
    error_message = "image_datastore_id must not be empty."
  }
}

variable "image_datastore_path" {
  description = "Absolute directory path on the node that backs the storage."
  type        = string

  validation {
    condition     = startswith(var.image_datastore_path, "/")
    error_message = "image_datastore_path must be an absolute path."
  }
}
