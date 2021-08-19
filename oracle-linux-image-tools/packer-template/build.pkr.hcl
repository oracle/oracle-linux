build {
  sources = [
    "virtualbox-iso.x86-64",
    "qemu.x86-64",
  ]
  provisioner "file" {
    source      = var.packer_files
    destination = "/tmp"

  }
  provisioner "shell" {
    script = var.provision_script
  }
}
