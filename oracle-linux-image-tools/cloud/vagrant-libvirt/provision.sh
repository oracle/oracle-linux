#!/usr/bin/env bash
#
# Packer provisioning script for Vagrant-libvirt
#
# Copyright (c) 2020 Oracle and/or its affiliates.
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
# Install NFS client (needed for shared /vagrant folder)
# Globals:
#   YUM_VERBOSE
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::install_agent()
{
  echo_message "Install NFS client"
  yum install -y "${YUM_VERBOSE}" nfs-utils
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
