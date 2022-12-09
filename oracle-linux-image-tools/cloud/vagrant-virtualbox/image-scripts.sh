#!/usr/bin/env bash
#
# Cleanup and package image for the "vagrant-virtualbox" image
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
    cat >>"$1" <<-EOF
			guest_additions_url    = "${VAGRANT_GUEST_ADDITIONS_URL}"
			guest_additions_sha256 = "${VAGRANT_GUEST_ADDITIONS_SHA256}"
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
# cloud::image_cleanup() {
#   :
# }

#######################################
# Image packaging: generate box using vagrant tool
# Globals:
#   ORACLE_RELEASE
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
  if [[ "${ORACLE_RELEASE}" =~ ^[89]$ ]]; then
    # For OL8/OL9 as we don't have image_cleanup (we use distr::seal), we can
    # import directrly the saved OVA file.
    rm System.img
    vboxmanage import System.ova \
      --vsys 0 --vmname "${VM_NAME}" \
      --vsys 0 --ostype "Oracle_64" \
      --vsys 0 --cpus "$cpu" \
      --vsys 0 --memory "$memory"
  else
    # convert back to VMDK
    local vmdk
    vmdk=$(grep "ovf:href" "${VM_NAME}.ovf" | sed -r -e 's/.*ovf:href="([^"]+)".*/\1/')
    common::convert_to_vmdk "${vmdk}"
    # re-create the OVA file
    common::make_ova "${VM_NAME}.ovf" "${vmdk}"
    # Import in VirtualBox and adjust cpu/memory for the box
    vboxmanage import "${VM_NAME}.ova" \
      --vsys 0 --vmname "${VM_NAME}" \
      --vsys 0 --ostype "Oracle_64" \
      --vsys 0 --cpus "$cpu" \
      --vsys 0 --memory "$memory"
    rm "${VM_NAME}.ova"
  fi
  # Add additional disk
  if [[ -n $VAGRANT_VIRTUALBOX_EXTRA_DISK_GB ]]; then
    local disk_size_mb=$(( VAGRANT_VIRTUALBOX_EXTRA_DISK_GB * 1024 ))
    vboxmanage createhd --filename ./extra_disk.vdi --size $disk_size_mb --format VDI --variant fixed
    vboxmanage storageattach "${VM_NAME}" --storagectl "SATA Controller" --port 1 --device 0 --type hdd --medium ./extra_disk.vdi
  fi
  # Create the box
  if [[ "${ORACLE_RELEASE}" =~ ^[89]$ ]]; then
    # For the latest uek kernels (UEK7) we install kernel-uek-core which only has virtio drivers...
    cat > Vagrantfile <<-EOF
			Vagrant.configure("2") do |config|
			  config.vm.provider :virtualbox do |v|
			    v.default_nic_type = "virtio"
			  end
			end
		EOF
    vagrant package --base "${VM_NAME}" --output "${VM_NAME}.box" --vagrantfile Vagrantfile
    rm -rf Vagrantfile .vagrant
  else
    vagrant package --base "${VM_NAME}" --output "${VM_NAME}.box"
  fi
  vboxmanage unregistervm "${VM_NAME}" --delete
}
