#!/usr/bin/env bash
#
# Packer provisioning script for Azure
#
# Copyright (c) 2019 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# Description: Azure specific provisioning. This module provides 2 functions,
# both are optional.
#   cloud::provision: provision the instance
#   cloud::cleanup: instance cleanup before shutdown
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

#######################################
# Install the Microsoft Azure Linux Agent
# Globals:
#   YUM_VERBOSE
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::install_WALinuxAgent()
{
  echo_message "Install Microsoft Azure Linux Agent"
  if [[ "${ORACLE_RELEASE}" = "7" ]]; then
    yum install -y "${YUM_VERBOSE}" parted python-pyasn1 hypervkvpd
    yum install -y "${YUM_VERBOSE}" --enablerepo ol7_addons WALinuxAgent dnsmasq
    yum remove -y "${YUM_VERBOSE}" dracut-config-rescue
  elif [[ "${ORACLE_RELEASE}" = "8" ]]; then
    dnf install -y parted hypervkvpd
    dnf install -y WALinuxAgent dnsmasq
    if [[ -z "${RESCUE_KERNEL}" || "${RESCUE_KERNEL,,}" = "no" ]]; then
      dnf remove -y dracut-config-rescue
    fi
  else
    echo "Unsupported OL version"
    exit
  fi

  systemctl enable waagent

  # Configure waagent to add 2GB swap space for all instances by default
  sed -i -e "s/ResourceDisk.EnableSwap.*/ResourceDisk.EnableSwap=y/" /etc/waagent.conf
  sed -i -e "s/ResourceDisk.SwapSizeMB.*/ResourceDisk.SwapSizeMB=2048/" /etc/waagent.conf
}

#######################################
# Configuration of the Azure image
# Globals:
#   AZURE_DBLICENSE
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::azure_cfg()
{
  echo_message "Configure networking"
  # Simple eth0 config, again not hard-coded to the build hardware
  cat > /etc/sysconfig/network-scripts/ifcfg-eth0 <<-EOF
	DEVICE=eth0
	ONBOOT=yes
	BOOTPROTO=dhcp
	TYPE=Ethernet
	USERCTL=no
	PEERDNS=yes
	IPV6INIT=no
	EOF

  if [[ "${ORACLE_RELEASE}" = "7" ]]; then
    echo "NM_CONTROLLED=no" >>/etc/sysconfig/network-scripts/ifcfg-eth0
  fi

  # Disable NetworkManager handling of the SRIOV interfaces
  # Fix for Bug 16391: For Accelerated Networking Azure, use udev rule to prevent Hyper-V PCI device renaming
  cat <<-EOF > /etc/udev/rules.d/68-azure-sriov-nm-unmanaged.rules
	# Accelerated Networking on Azure exposes a new SRIOV interface to the VM.
	# This interface is transparently bonded to the synthetic interface,
	# so NetworkManager should just ignore any SRIOV interfaces.
	SUBSYSTEM=="net", DRIVERS=="hv_pci", ACTION=="add", ENV{NM_UNMANAGED}="1"
	EOF

  echo_message "Disable unneeded services"
  systemctl disable wpa_supplicant || true
  systemctl disable iptables || true
  systemctl disable ip6tables || true
  echo_message "Enable required services"
  systemctl enable network || true
  systemctl enable dnsmasq || true

  echo_message "Configure grub"
  grubby --update-kernel=ALL --args="console=tty1 console=ttyS0,115200n8 earlyprintk=ttyS0,115200 rootdelay=300 net.ifnames=0"
  sed -i 's/^\(GRUB_CMDLINE_LINUX\)=".*"$/\1="console=tty1 console=ttyS0,115200n8 earlyprintk=ttyS0,115200 rootdelay=300 net.ifnames=0"/g' /etc/default/grub
  sed -i 's/^#\(ClientAliveInterval\).*$/\1 180/g' /etc/ssh/sshd_config

  echo_message "Update EULA"
  cp "/tmp/packer_files/cloud/${AZURE_DBLICENSE}" /usr/share/oraclelinux-release/EULA
  cp "/tmp/packer_files/cloud/${AZURE_DBLICENSE}" /usr/share/eula/eula.en_US
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
  cloud::install_WALinuxAgent
  cloud::azure_cfg
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
  waagent -force -deprovision
}
