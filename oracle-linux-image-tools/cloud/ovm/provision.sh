#!/usr/bin/env bash
#
# Packer provisioning script for OVM
#
# Copyright (c) 1982-2019 Oracle and/or its affiliates. All rights reserved.
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
# Configure OVM instance
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::ovm_cfg()
{
  echo_message "Setup network"
  # simple eth0 config, again not hard-coded to the build hardware
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

  echo_message 'Configure grub"'
  cat > /etc/default/grub  <<-EOF
	GRUB_TIMEOUT=10
	GRUB_HIDDEN_MENU_QUIET=false
	GRUB_DEFAULT=saved
	GRUB_DISABLE_SUBMENU=true
	GRUB_TERMINAL="serial console"
	GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
	GRUB_CMDLINE_LINUX="console=tty0"
	GRUB_DISABLE_RECOVERY="true"
	EOF

  #Regenerate grub.cfg
  grub2-mkconfig -o /boot/grub2/grub.cfg
}

#######################################
# Install vmapi and libxenstore
# Globals:
#   YUM_VERBOSE
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::install_vmapilibxenstore()
{
  echo_message "Install OVM API and LibXenStore"
  yum install --enablerepo ol7_addons -y ${YUM_VERBOSE} libovmapi \
    libovmapi-devel \
    ovmd \
    ovm-template-config \
    ovm-template-config-authentication \
    ovm-template-config-datetime \
    ovm-template-config-firewall \
    ovm-template-config-network \
    ovm-template-config-selinux \
    ovm-template-config-ssh \
    ovm-template-config-system \
    ovm-template-config-user \
    python-simplejson \
    xenstoreprovider

  sed -i -e 's/^INITIAL_CONFIG.*/INITIAL_CONFIG=yes/' /etc/sysconfig/ovm-template-initial-config

  yum install --enablerepo ol7_addons -y ${YUM_VERBOSE} libxenstore
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
cloud::provision()
{
  cloud::install_vmapilibxenstore
  cloud::ovm_cfg
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
