#!/usr/bin/env bash
#
# Cleanup and package image for the "vagrant-virtualbox" image
#
# Copyright (c) 2020 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
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
#   VAGRANT_VIRTUALBOX_CPU, VAGRANT_VIRTUALBOX_MEMORY,
#   VAGRANT_VIRTUALBOX_EXTRA_DISK_GB
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::validate() {
  [[ ${VAGRANT_VIRTUALBOX_CPU_NUM} =~ ^[0-9]*$ ]]  || error "vagrant cpu count is not numeric"
  [[ ${VAGRANT_VIRTUALBOX_MEM_SIZE} =~ ^[0-9]*$ ]]  || error "vagrant memory is not numeric"
  [[ ${VAGRANT_VIRTUALBOX_EXTRA_DISK_GB} =~ ^[0-9]*$ ]]  || error "vagrant disk size is not numeric"
  [[ ${VAGRANT_DEVELOPER_REPOS,,} =~ ^(yes)|(no)$ ]] || error "VAGRANT_DEVELOPER_REPOS must be Yes or No"
}

#######################################
# Packer configuration
# Globals:
#   VAGRANT_GUEST_ADDITIONS_URL
#   VAGRANT_GUEST_ADDITIONS_SHA256
# Arguments:
#   Packer configuration file
# Returns:
#   None
#######################################
cloud::packer_conf() {
  if [[ -n "${VAGRANT_GUEST_ADDITIONS_URL}" && -n "${VAGRANT_GUEST_ADDITIONS_SHA256}" ]]; then
    ex -s "$1" <<-EOF
	/"disk_size": /
	:append
	      "guest_additions_url": "${VAGRANT_GUEST_ADDITIONS_URL}",
	      "guest_additions_sha256": "${VAGRANT_GUEST_ADDITIONS_SHA256}",
	.
	:update
	:quit
	EOF
  fi
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
cloud::image_cleanup() {
  :
}

#######################################
# Image packaging: generate box using vagrant tool
# Globals:
#   VM_NAME, VAGRANT_VIRTUALBOX_CPU, VAGRANT_VIRTUALBOX_MEMORY,
#   VAGRANT_VIRTUALBOX_EXTRA_DISK_GB
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::image_package() {
  local cpu="${VAGRANT_VIRTUALBOX_CPU_NUM:-$CPU_NUM}"
  local memory="${VAGRANT_VIRTUALBOX_MEM_SIZE:-$MEM_SIZE}"
  # convert back to VMDK
  local vmdk=$(grep "ovf:href" "${VM_NAME}.ovf" | sed -r -e 's/.*ovf:href="([^"]+)".*/\1/')
  vboxmanage convertfromraw System.img --format VMDK "${vmdk}" --variant Stream
  rm System.img
  # re-create the OVA file
  tar cvf "${VM_NAME}.ova" "${VM_NAME}.ovf" "${vmdk}"
  rm "${vmdk}"
  # Import in VirtualBox and adjust cpu/memory for the box
  vboxmanage import "${VM_NAME}.ova" \
    --vsys 0 --vmname "${VM_NAME}" \
    --vsys 0 --ostype "Oracle_64" \
    --vsys 0 --cpus $cpu \
    --vsys 0 --memory $memory
  rm "${VM_NAME}.ova"
  # Add additional disk
  if [[ -n $VAGRANT_VIRTUALBOX_EXTRA_DISK_GB ]]; then
    local disk_size_mb=$(( ${VAGRANT_VIRTUALBOX_EXTRA_DISK_GB} * 1024 ))
    vboxmanage createhd --filename ./extra_disk.vdi --size $disk_size_mb --format VDI --variant fixed
    vboxmanage storageattach "${VM_NAME}" --storagectl "SATA Controller" --port 1 --device 0 --type hdd --medium ./extra_disk.vdi
  fi
  # Create the box
  vagrant package --base "${VM_NAME}" --output "${VM_NAME}.box"
  vboxmanage unregistervm "${VM_NAME}" --delete
}
