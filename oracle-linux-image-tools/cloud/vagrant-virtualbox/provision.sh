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

  # Search for guest additions ISO -- it is typically labeled VBox_...
  # Note: use "blkid -s" as "--match-tag" is not supported on OL7
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

  # Fake uname to build the kernel modules
  local default_kernel
  default_kernel=$(common::default_kernel)
  mv /usr/bin/uname /usr/bin/uname.orig
  cat > /usr/bin/uname <<-EOF
		#!/usr/bin/bash
		if [[ \$1 == "-r" ]]; then
		  echo "${default_kernel}"
		else
		  /usr/bin/uname.orig "\$@"
		fi
	EOF
  chmod 0755 /usr/bin/uname
  chcon --reference=/usr/bin/uname.orig /usr/bin/uname

  # Installation might fail when running in libguestfs environment
  sh "${additions}" || :
  umount /mnt

  # Restore uname
  rm /usr/bin/uname
  mv /usr/bin/uname.orig /usr/bin/uname
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
