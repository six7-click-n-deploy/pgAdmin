########################################
# CUSTOM-Variablen (Optional)
# Werden vom User gesetzt
########################################

variable "users" {
  description = "[CONTRACT] Teams mit User-Emails"
  type = map(list(object({
    email = string
  })))
  default = {}
}

########################################
# CONTRACT-Variablen (PFLICHT)
# Werden vom Worker/Platform gesetzt
########################################

variable "image_name" {
  description = "[BACKEND] Name des Packer-Images aus Glance (z.B. online-ide-v1) @openstack:image:name"
  type        = string
  default     = "pgadmin-vX"
}

variable "network_uuid" {
  description = "[BACKEND] UUID des internen Netzwerks (von Platform-Admin konfiguriert) @openstack:network:id"
  type        = string
  default     = "34a00b87-57ce-42c4-8e1b-9ea8a657ec2e"
}

variable "floating_ip_pool" {
  description = "[BACKEND] Name des External Networks für Floating IPs (von Platform-Admin konfiguriert) @openstack:floating_ip_pool:name"
  type        = string
  default     = "DHBW"
}

variable "shared_secgroup_id" {
  description = "[BACKEND] ID der gemeinsamen Security Group für alle VMs @openstack:security_group:id"
  type        = string
  default     = "4ffaf007-df66-4250-9118-1bd99378d34a"
}
