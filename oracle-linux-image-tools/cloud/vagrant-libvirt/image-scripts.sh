#!/usr/bin/env bash
#
# Cleanup and package image for the "vagrant-libvirt" image
#
# Copyright (c) 2020, 2022 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# Description: this module provides 2 functions:
#   cloud::image_cleanup: cloud specific actions to cleanup the image
#     This function is optional
#   cloud::image_package: Package the raw image for the target cloud.
#     This function must be defined either at cloud or cloud/distribution level
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

#######################################
# Parameter validation
# Globals:
#   VAGRANT_LIBVIRT_BOX_SCRIPT
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::validate() {
  [[ -n ${VAGRANT_LIBVIRT_BOX_SCRIPT} && -x ${VAGRANT_LIBVIRT_BOX_SCRIPT} ]]  || error "missing vagrant box_create script"
  [[ ${VAGRANT_LIBVIRT_CPU_NUM} =~ ^[0-9]*$ ]]  || error "vagrant cpu count is not numeric"
  [[ ${VAGRANT_LIBVIRT_MEM_SIZE} =~ ^[0-9]*$ ]]  || error "vagrant memory is not numeric"
  [[ ${VAGRANT_DEVELOPER_REPOS,,} =~ ^(yes)|(no)$ ]] || error "VAGRANT_DEVELOPER_REPOS must be Yes or No"
}

#######################################
# Cleanup actions run directly on the image
# Globals:
#   None
# Arguments:
#   root filesystem directory
#   boot filesystem directory
# Returns:
#   None
#######################################
# cloud::image_cleanup() {
#   :
# }

#######################################
# Image packaging: generate box using vagrant tool
# Globals:
#   VM_NAME
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::image_package() {
  local cpus="${VAGRANT_LIBVIRT_CPU_NUM:-$CPU_NUM}"
  local memory="${VAGRANT_LIBVIRT_MEM_SIZE:-$MEM_SIZE}"

  common::convert_to_qcow2 "${VM_NAME}.qcow"

  # Defaults for the box
  cat > Vagrantfile <<-EOF
  config.vm.provider :libvirt do |libvirt|
    libvirt.memory = ${memory}
    libvirt.cpus = ${cpus}
    libvirt.features = ['apic', 'acpi']
    libvirt.video_vram = 16384
  end

  config.vm.synced_folder ".", "/vagrant",
    type: "nfs",
    nfs_version: 3,
    nfs_udp: false
EOF
  ${VAGRANT_LIBVIRT_BOX_SCRIPT} "${VM_NAME}.qcow" "${VM_NAME}.box" Vagrantfile
  rm "${VM_NAME}.qcow" Vagrantfile
}
