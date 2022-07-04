# x86-64 build with qemu-kvm

source "qemu" "x86-64" {
  accelerator          = "kvm"
  iso_url              = var.iso_url
  iso_checksum         = var.iso_checksum
  output_directory     = local.output_directory
  vm_name              = "System.img"
  net_device           = "virtio-net"
  disk_interface       = "virtio-scsi"
  disk_size            = var.disk_size
  cpus                 = var.cpus
  memory               = var.memory
  format               = "raw"
  headless             = "true"
  ssh_username         = "root"
  ssh_password         = var.ssh_password
  ssh_private_key_file = var.ssh_private_key_file
  ssh_port             = 22
  ssh_wait_timeout     = "30m"
  http_directory       = local.http_directory
  boot_wait            = "20s"
  boot_command         = var.boot_command
  shutdown_command     = var.shutdown_command
  qemu_binary          = var.qemu_binary
  qemuargs             =  concat(
    var.qemu_args,
    [
      ["-cpu", "host"]
    ]
  )
}
