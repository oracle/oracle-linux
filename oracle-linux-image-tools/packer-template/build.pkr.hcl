build {
  sources = [
    "virtualbox-iso.x86-64",
    "qemu.x86-64",
    "qemu.aarch64",
  ]
  provisioner "file" {
    source      = var.packer_files
    destination = "/tmp"

  }
  provisioner "shell" {
    script = var.provision_script
    environment_vars = [
      "OLIT_ACTION=provision",
    ]
  }
  provisioner "file" {
    only        = local.get_build_info
    direction   = "download"
    source      = "${var.build_info}/*"
    destination = "${local.output_directory}/"
  }
  provisioner "shell" {
    script = var.provision_script
    environment_vars = [
      "OLIT_ACTION=seal",
    ]
  }
}
