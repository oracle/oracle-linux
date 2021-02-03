#!/usr/bin/env bash
#
# Packer provisioning script for OVM on OL8
#
# Copyright (c) 2020, 2021, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# Description: OVM on OL8 specific provisioning. This module provides 2
# functions, both are optional.
#   cloud_distr::provision: provision the instance
#   cloud_distr::cleanup: instance cleanup before shutdown
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

#######################################
# Configure serial ports
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud_distr::serial_cfg() {
  cat > /usr/lib/systemd/system/serial_console.service <<-EOF
	#  This file is part of systemd.
	#
	#  systemd is free software; you can redistribute it and/or modify it
	#  under the terms of the GNU Lesser General Public License as published by
	#  the Free Software Foundation; either version 2.1 of the License, or
	#  (at your option) any later version.

	[Unit]
	Description=Serial Getty on serial_console
	Documentation=man:agetty(8) man:systemd-getty-generator(8)
	Documentation=http://0pointer.de/blog/projects/serial-console.html
	BindsTo=dev-serial_console.device
	After=dev-%i.device systemd-user-sessions.service plymouth-quit-wait.service
	After=rc-local.service

	# If additional gettys are spawned during boot then we should make
	# sure that this is synchronized before getty.target, even though
	# getty.target didn't actually pull it in.
	Before=getty.target
	IgnoreOnIsolate=yes
	Conflicts=serial-getty@ttyS0.service serial-getty@hvc0.service
	ConditionPathIsSymbolicLink=/dev/serial_console

	[Service]
	ExecStart=-/sbin/agetty --keep-baud 115200,38400,9600 serial_console $TERM
	Type=idle
	Restart=always
	UtmpIdentifier=serial_console
	TTYPath=/dev/serial_console
	TTYReset=yes
	TTYVHangup=yes
	KillMode=process
	IgnoreSIGPIPE=no
	SendSIGHUP=yes

	[Install]
	WantedBy=getty.target
	EOF

  echo "KERNEL==\"ttyS0\", DEVPATH==\"/devices/pnp0/*\", SYMLINK+=\"serial_console\"" > /etc/udev/rules.d/50-udev.rules
  echo "KERNEL==\"hvc0\", DEVPATH==\"/devices/virtual/*\", SYMLINK+=\"serial_console\"" >> /etc/udev/rules.d/50-udev.rules
  systemctl enable serial_console.service
}

#######################################
# Configure additional kernel
# This will install RHCK if UEK is already there or the opposite
# Assumes that we have a single kernel installed
# Globals:
#   DRACUT_CMD, KERNEL
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud_distr::additional_kernel() {
  local kernel kernel_version

  # Select kernel to install
  # shellcheck disable=SC2153
  if [[ "${KERNEL,,}" = "uek" ]]; then
    kernel="kernel"
  else
    kernel="kernel-uek"
    dnf config-manager --set-enabled ol8_UEKR6
  fi

  echo_message "Adding kernel: ${kernel}"
  # Cleanup dracut config, as it is customized for the "other" kernel
  rm /etc/dracut.conf.d/01-dracut-vm.conf
  dnf install -y ${kernel}
  kernel_version=$(rpm -q ${kernel} --qf "%{VERSION}-%{RELEASE}.%{ARCH}")
  echo_message "Installed kernel: ${kernel_version}"

  # Add virtual drivers 
  local virtio modules
  modules=$(find "/lib/modules/${kernel_version}" -name "virtio*.ko*" -printf '%f\n')
  while read -r module; do
    virtio="${virtio} ${module%.ko*}"
  done <<<"${modules}"

  cat > /etc/dracut.conf.d/01-dracut-vm.conf <<-EOF
	add_drivers+=" xen_netfront xen_blkfront "
	add_drivers+=" ${virtio} "
	add_drivers+=" hyperv_keyboard hv_netvsc hid_hyperv hv_utils hv_storvsc hyperv_fb "
	add_drivers+=" ahci libahci "
	EOF

  # Regenerate initrd
  ${DRACUT_CMD} -f "/boot/initramfs-${kernel_version}.img" "${kernel_version}"

  # Cleanup dracut config, it is only needed for the initial build
  rm /etc/dracut.conf.d/01-dracut-vm.conf

  # Ensure grub is properly setup
  grub2-mkconfig -o /boot/grub2/grub.cfg
}

#######################################
# Provisioning module
# Globals:
#   EXTRA_KERNEL
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud_distr::provision()
{
  cloud_distr::serial_cfg
  if [[ "${EXTRA_KERNEL,,}" = "yes" ]]; then
    cloud_distr::additional_kernel
  fi
}

#######################################
# Cleanup module
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud_distr::cleanup()
{
  :
}
