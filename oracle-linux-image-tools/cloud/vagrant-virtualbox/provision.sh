#!/usr/bin/env bash
#
# Packer provisioning script for Vagrant-VirtualBox
#
# Copyright (c) 2020, 2022 Oracle and/or its affiliates.
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
source /tmp/packer_files/cloud/vagrant-common.sh

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
#   KERNEL, YUM_VERBOSE
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::install_agent()
{
  echo_message "Install guest agent"
  local additions="/mnt/VBoxLinuxAdditions.run"
  yum install -y "${YUM_VERBOSE}" make gcc bzip2 tar

  if [[ "${KERNEL,,}" = "uek" ]]; then
    yum install -y "${YUM_VERBOSE}" kernel-uek-devel
  else
    yum install -y "${YUM_VERBOSE}" kernel-devel
  fi

  # Orabug 34811820 for OL8 UEK7 -- for the current install
  case $(uname -r) in
    5.15.0-*.el8uek*)
      export PATH="/opt/rh/gcc-toolset-11/root/usr/bin:$PATH"
  esac

  # Search for guest additions on cd devices
  for cdrom in /dev/sr*; do
    if mount -o ro "${cdrom}" /mnt; then
      if [[ -f ${additions} ]]; then
        # Found!
        break
      else
        echo_message "No guest additions on ${cdrom}"
      fi
    else
      echo_message "No media in ${cdrom}"
    fi
  done

  [[ -f ${additions} ]] || echo_error "Guest additions not found"

  sh "${additions}" || :
  umount /mnt

  # Orabug 34811820 for OL8 UEK7 -- for subsequent rebuilds
  case $(uname -r) in
    5.15.0-*.el8uek*)
      # shellcheck disable=SC2016
      sed -i '/PATH=$PATH/a PATH="/opt/rh/gcc-toolset-11/root/usr/bin:$PATH"' /usr/sbin/rcvboxadd
  esac

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
