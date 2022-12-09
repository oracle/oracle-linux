# aarch64 build with qemu-kvm

# Hack to get cached file name
# Needed to workaround https://github.com/hashicorp/packer-plugin-qemu/issues/35
# This will only work for remote files as local file are not cached! For local
# files, copy the ISO directly in the cache directory...
variable "cache_dir" {
  description = "Packer cache directory"
  type = string
  default = env("PACKER_CACHE_DIR") == "" ? "./packer_cache" : env("PACKER_CACHE_DIR")
}

locals {
  iso_basename = regex("[^/]*$", var.iso_url)
}

# KVM or TCG?
variable "accel" {
  description = "Set accel to kvm if kvm is available"
  type = string
  default = ""
}

locals {
  accel = var.accel == "kvm" ? "kvm" : "tcg"
  cpu = var.accel == "kvm" ? "host" : "cortex-a57"
}

source "qemu" "aarch64" {
  iso_url              = var.iso_url
  iso_checksum         = var.iso_checksum
  iso_target_path      = "${var.cache_dir}/${local.iso_basename}"
  output_directory     = local.output_directory
  vm_name              = "System.img"
  net_device           = "virtio-net"
  cdrom_interface      = "virtio-scsi"
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
  ssh_wait_timeout     = "180m"
  http_directory       = local.http_directory
  boot_wait            = "20s"
  boot_command         = var.boot_command
  shutdown_command     = var.shutdown_command
  qemu_binary          = var.qemu_binary
  qemuargs = concat(
    var.qemu_args,
    [
      ["-machine", "virt-rhel8.2.0,accel=${local.accel},dump-guest-core=off,gic-version=2,pflash0=libvirt-pflash0-format"],
      ["-cpu", local.cpu],
      [
        "-blockdev",
        <<-EOT
          {
            "driver": "raw",
            "node-name": "libvirt-pflash0-format",
            "file":
              {
                "driver": "file",
                "node-name": "libvirt-pflash0-storage",
                "filename": "/usr/share/edk2/aarch64/QEMU_EFI-silent-pflash.raw",
                "auto-read-only": true,
                "discard":"unmap"
              },
            "read-only": true
          }
        EOT
      ],
      ["-boot", "strict=on"],
      ["-device", "virtio-gpu-pci,id=video0,max_outputs=1"],
      ["-device", "virtio-net,netdev=user.0"],
      ["-device", "virtio-scsi-pci,id=scsi0"],
      ["-device", "scsi-hd,bus=scsi0.0,scsi-id=0,drive=drive0"],
      ["-device", "scsi-cd,drive=cdrom0"],
      ["-device", "qemu-xhci,p2=15,p3=15,id=usb"],
      ["-device", "usb-kbd,id=input1"],
      ["-drive", "if=none,file=${var.cache_dir}/${local.iso_basename},index=1,id=cdrom0,media=cdrom"],
      ["-drive", "if=none,file=${local.output_directory}/System.img,id=drive0,cache=writeback,discard=ignore,format=raw"]
    ]
  )
}
