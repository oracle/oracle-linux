#!/usr/bin/env bash
#
# Provisioning script for OVM on OL9
#
# Copyright (c) 2023, 2025 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# Description: OVM on OL9 specific provisioning. This module provides 2
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
  cat > /usr/lib/systemd/system/serial_console.service <<-'EOF'
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
#   DRACUT_CMD, KERNEL, KERNEL_MODULES
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
    if [[ ${KERNEL_MODULES,,} == "yes" ]]; then
      kernel="kernel-uek"
    else
      kernel="kernel-uek-core"
    fi
    dnf config-manager --set-enabled "ol9_UEKR7"
  fi

  common::echo_message "Adding kernel: ${kernel}"
  dnf install -y ${kernel}
  kernel_version=$(rpm -q ${kernel} --qf "%{VERSION}-%{RELEASE}.%{ARCH}")
  common::echo_message "Installed kernel: ${kernel_version}"

  # Regenerate initrd
  ${DRACUT_CMD} -f "/boot/initramfs-${kernel_version}.img" "${kernel_version}"

  # Ensure grub is properly setup
  grub2-mkconfig -o /boot/grub2/grub.cfg --update-bls-cmdline
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
