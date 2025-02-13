#!/usr/bin/env bash
#
# Provisioning script for Vagrant-VirtualBox
#
# Copyright (c) 2020, 2025 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# Description: Vagrant specific provisioning. This module provides 2 functions,
# both are optional.
#   cloud::provision: provision the instance
#   cloud::cleanup: instance cleanup before shutdown
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

# Load vagrant common scripts
# shellcheck disable=SC1091
source "${PROVISION_DIR}/cloud/vagrant-common.sh"

#######################################
# Configure Vagrant instance
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::config()
{
  vagrant::config
}

#######################################
# Install Virtualbox guest agent
# Globals:
#   YUM_VERBOSE
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::install_agent()
{
  common::echo_message "Install Guest Additions"
  local additions
  if [[ $(uname -i) == "aarch64" ]]; then
    additions="/mnt/VBoxLinuxAdditions-arm64.run"
  else
    additions="/mnt/VBoxLinuxAdditions.run"
  fi
  yum install -y "${YUM_VERBOSE}" make gcc bzip2 tar

  if [[ "${KERNEL,,}" = "uek" ]]; then
    yum install -y "${YUM_VERBOSE}" kernel-uek-devel
  else
    yum install -y "${YUM_VERBOSE}" kernel-devel
  fi

  # Orabug 34811820 for OL8 UEK7 -- for the current install
  case $(common::default_kernel) in
    5.15.0-*.el8uek*)
      export PATH="/opt/rh/gcc-toolset-11/root/usr/bin:$PATH"
  esac

  # Search for guest additions ISO -- it is typically labeled VBox_...
  # Note: use "blkid -s" as "--match-tag" is not suported on OL7
  local label
  for label in $(/sbin/blkid -s LABEL -o value | grep VBox_); do
    if mount -o ro LABEL="${label}" /mnt; then
      if [[ -f ${additions} ]]; then
        # Found!
        break
      else
        common::echo_message "No guest additions on ${label}"
        umount /mnt
      fi
    else
      common::echo_message "Cannot mount ${label}"
    fi
  done

  [[ -f ${additions} ]] || common::error "Guest additions not found"

  # Installation will fail when running in libguestfs environment
  sh "${additions}" || :
  umount /mnt

  # Orabug 34811820 for OL8 UEK7 -- for subsequent rebuilds
  case $(common::default_kernel) in
    5.15.0-*.el8uek*)
      # shellcheck disable=SC2016
      sed -i '/PATH=$PATH/a PATH="/opt/rh/gcc-toolset-11/root/usr/bin:$PATH"' /usr/sbin/rcvboxadd
      for ga in /opt/VBoxGuestAdditions*; do
        cp /usr/sbin/rcvboxadd "${ga}/init/vboxadd"
      done
  esac

  # Ensure modules are built for the target kernel
  if [[ $(uname -r) != $(common::default_kernel) ]]; then
    common::echo_message "Building Guest Additions for $(common::default_kernel)"
    /sbin/rcvboxadd quicksetup "$(common::default_kernel)"
  fi

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
  cloud::install_agent
  cloud::config
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
  vagrant::cleanup
}
