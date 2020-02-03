#!/usr/bin/env bash
#
# Packer provisioning script for OLVM
#
# Copyright (c) 1982-2020 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# Description: OVM specific provisioning. This module provides 2 functions,
# both are optional.
#   cloud::provision: provision the instance
#   cloud::cleanup: instance cleanup before shutdown
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

#######################################
# Provisioning module
# Globals:
#   YUM_VERBOSE
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::provision()
{
  echo_message "Setup network"
  # simple eth0 configuration
  cat > /etc/sysconfig/network-scripts/ifcfg-eth0 <<-EOF
	DEVICE="eth0"
	BOOTPROTO="dhcp"
	ONBOOT="yes"
	TYPE="Ethernet"
	USERCTL="yes"
	PEERDNS="yes"
	IPV6INIT="no"
	PERSISTENT_DHCLIENT="1"
	EOF

  echo_message "Install guest agent"
  yum install -y ${YUM_VERBOSE} qemu-guest-agent
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
cloud::cleanup()
{
  :
}
