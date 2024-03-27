#!/usr/bin/env bash
#
# Provisioning script for OCI / OL8
#
# Copyright (c) 2024 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# Description: OCI/OL8 specific provisioning.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#


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
  # There is an issue with the Oracle cloud-init datasource in cloud-init 23.x
  # We need to ensure network is already up before running cloud-init.
  sed -i 's/^\(GRUB_CMDLINE_LINUX\)="\(.*\)"$/\1="\2 rd.neednet"/' /etc/default/grub
  grub2-mkconfig -o /boot/grub2/grub.cfg
}
