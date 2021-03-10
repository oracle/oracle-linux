#!/usr/bin/env bash
#
# Packer provisioning script for OVM
#
# Copyright (c) 2019,2020 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# Description: OVM specific provisioning. This module provides 2 functions,
# both are optional.
#   cloud::provision: provision the instance
#   cloud::cleanup: instance cleanup before shutdown
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

cloud::default_grub()
#######################################
# Set values in /etc/default/grub
# Globals:
#   None
# Arguments:
#   Key: key to set
#   Value: value
# Returns:
#   None
#######################################
{
  key="$1"
  value="$2"

  if grep -q "^${key}=" /etc/default/grub; then
    # Replace parameter
    sed -i -e "s/^${key}=.*/${key}=${value}/" /etc/default/grub
  else
    # Add parameter
    echo "${key}=${value}" >> /etc/default/grub
  fi
}

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

  echo_message 'Configure grub'
  cloud::default_grub GRUB_TIMEOUT 10
  # GRUB_HIDDEN_MENU_QUIET: for historical reason, not used anymore...
  cloud::default_grub GRUB_HIDDEN_MENU_QUIET false
  cloud::default_grub GRUB_SERIAL_COMMAND '"serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"'
  sed -i -e '/^GRUB_TERMINAL/d' /etc/default/grub
  cloud::default_grub GRUB_TERMINAL '"serial console"'

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
  if [[ "${ORACLE_RELEASE}" = "7" ]]; then
    yum install --enablerepo ol7_addons -y "${YUM_VERBOSE}" \
      libovmapi \
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
      xenstoreprovider \
      libxenstore
  elif [[ "${ORACLE_RELEASE}" = "8" ]]; then
    dnf install --enablerepo ol8_addons -y \
      libovmapi \
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
      xenstoreprovider
  else
    echo "Unsupported OL version"
    exit
  fi

  sed -i -e 's/^INITIAL_CONFIG.*/INITIAL_CONFIG=yes/' /etc/sysconfig/ovm-template-initial-config
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
