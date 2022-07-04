# x86-64 build with VirtualBox

source "virtualbox-iso" "x86-64" {
  guest_os_type          = "Oracle_64"
  iso_url                = var.iso_url
  iso_checksum           = var.iso_checksum
  output_directory       = local.output_directory
  vm_name                = var.vm_name
  hard_drive_interface   = "sata"
  disk_size              = var.disk_size
  guest_additions_mode   = "attach"
  guest_additions_url    = var.guest_additions_url
  guest_additions_sha256 = var.guest_additions_sha256
  format                 = "ova"
  headless               = "true"
  ssh_username           = "root"
  ssh_password           = var.ssh_password
  ssh_private_key_file   = var.ssh_private_key_file
  ssh_port               = 22
  ssh_wait_timeout       = "30m"
  http_directory         = local.http_directory
  boot_wait              = "20s"
  boot_command           = var.boot_command
  shutdown_command       = var.shutdown_command
  vboxmanage = concat(
    var.vbox_manage,
    [
      ["modifyvm", "{{.Name}}", "--x2apic", var.x2apic],
      ["modifyvm", "{{.Name}}", "--memory", var.memory],
      ["modifyvm", "{{.Name}}", "--cpus", var.cpus],
      ["modifyvm", "{{.Name}}", "--nictype1", "virtio"],
    ]
  )
  vboxmanage_post = [
    ["modifyvm", "{{.Name}}", "--uart1", "off", "--uartmode1", "disconnected"],
    ["modifyvm", "{{.Name}}", "--x2apic", "on"],
  ]
}
