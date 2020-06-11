#!/usr/bin/env bash
#
# Packer provisioning script for OVM on OL7
#
# Copyright (c) 2019 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# Description: OVM on OL7 specific provisioning. This module provides 2
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
# Provisioning module
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud_distr::provision()
{
  cloud_distr::serial_cfg
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
