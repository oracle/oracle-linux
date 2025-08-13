#!/usr/bin/env bash
#
# Cleanup and package image for the "vagrant-libvirt" image
#
# Copyright (c) 2020, 2025 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# Description: this module provides the following functions which are run on
# the host:
#   cloud::validate: called at the very beginning to validate project parameters
#     (optional)
#   cloud::customize_args: arguments to pass to virt-customize (optional)
#   cloud::sysprep_args: arguments to pass to virt-sysprep (optional)
#   cloud::image_package: Package the raw image for the target cloud.
#     This function must be defined either at cloud or cloud/distribution level
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

#######################################
# Parameter validation
# Globals:
#   VAGRANT_LIBVIRT_BOX_SCRIPT  VAGRANT_DEVELOPER_REPOS
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::validate() {
  [[ -n ${VAGRANT_LIBVIRT_BOX_SCRIPT} && -x ${VAGRANT_LIBVIRT_BOX_SCRIPT} ]] ||
    common::error "missing vagrant box_create script"
  [[ ${VAGRANT_DEVELOPER_REPOS,,} =~ ^((yes)|(no))$ ]] ||
    common::error "VAGRANT_DEVELOPER_REPOS must be Yes or No"
}

#######################################
# virt-sysprep arguments
# Globals:
#   None
# Arguments:
#   virt-sysprep argument nameref
# Returns:
#   None
#######################################
cloud::sysprep_args() {
  declare -n sysprep_args="$1"
  # Default insecure vagrant key
  sysprep_args+=( --ssh-inject "vagrant:string:ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key" )
}

#######################################
# Image packaging: generate box using vagrant tool
# Globals:
#   CPU_NUM, MEM_SIZE, VAGRANT_LIBVIRT_BOX_SCRIPT, VAGRANT_LIBVIRT_CPU_NUM
#   VAGRANT_LIBVIRT_MEM_SIZE, VM_NAME
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::image_package() {
  local cpus="${VAGRANT_LIBVIRT_CPU_NUM:-${CPU_NUM%%,*}}"
  local memory="${VAGRANT_LIBVIRT_MEM_SIZE:-$MEM_SIZE}"

  pushd "${WORKSPACE}/${VM_NAME}" || common::error "can't cd to image directory"
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
  ${VAGRANT_LIBVIRT_BOX_SCRIPT} "${VM_NAME}.qcow2" "${VM_NAME}.box" Vagrantfile
  rm "${VM_NAME}.qcow2" Vagrantfile
  popd || common::error "can't pop directory"
}
