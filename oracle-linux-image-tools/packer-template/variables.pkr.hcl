# Variables and locals declaration

# Environment
variable "workspace" {
  description = "Workspace directory"
  type        = string
}

variable "packer_files" {
  description = "Directory for the provisioning files"
  type        = string
}

variable "provision_script" {
  description = "Provisioning script"
  type        = string
}

# ISO
variable "iso_url" {
  description = "URL of the ISO"
  type        = string
}

variable "iso_checksum" {
  description = "Checksum of the ISO"
  type        = string
}

# Generic VM properties
variable "vm_name" {
  description = "Name of the VM"
  type        = string
}

variable "disk_size" {
  description = "Disk size for the VM in MB"
  type        = number
}

variable "memory" {
  description = "Memory for the VM in MB"
  type        = number
}

variable "cpus" {
  description = "Number of CPUs for the VM in MB"
  type        = number
}

variable "ssh_password" {
  description = "Password for the root user"
  type        = string
  default     = null
}

variable "ssh_private_key_file" {
  description = "SSH private key file for the root user"
  type        = string
  default     = null
}

variable "boot_command" {
  description = "Boot command"
  type        = list(string)
}

variable "shutdown_command" {
  description = "shutdown_command"
  type        = string
}

# VirtualBox properties
variable "guest_additions_url" {
  description = "URL of the VirtualBox Guest Additions"
  type        = string
  default     = null
}

variable "guest_additions_sha256" {
  description = "Checksum of the VirtualBox Guest Additions"
  type        = string
  default     = null
}

variable "vbox_manage" {
  description = "VirtualBox vboxmanage aditional stanzas (for the serial console)"
  type        = list(list(string))
  default     = []
}

variable "x2apic" {
  description = "X2APIC for VirtualBox"
  type        = string
  default     = "on"
}

# QEMU properties
variable "qemu_binary" {
  description = "QEMU binary"
  type        = string
  default     = null
}

variable "qemu_args" {
  description = "QEMU Arguments"
  type        = list(list(string))
  default     = []
}

variable "build_info" {
  description = "Guest directory with build information"
  type        = string
  default     = ""
}

# Locals
locals {
  output_directory = "${var.workspace}/${var.vm_name}"
  http_directory   = var.workspace
  get_build_info   = var.build_info == "" ? [ "none" ] : []
}
