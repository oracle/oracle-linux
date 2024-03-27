#!/usr/bin/env bash
#
# Cleanup and package image for the "vagrant-virtualbox" image
#
# Copyright (c) 2020, 2024 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# Description: this module provides the following functions which are run on
# the host:
#   cloud::validate: called at the very begining to validate project parameters
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
#   VAGRANT_VIRTUALBOX_CPU, VAGRANT_VIRTUALBOX_MEMORY,
#   VAGRANT_VIRTUALBOX_EXTRA_DISK_GB
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::validate() {
  [[ ${VAGRANT_VIRTUALBOX_CPU_NUM} =~ ^[0-9]*$ ]]  || common::error "vagrant cpu count is not numeric"
  [[ ${VAGRANT_VIRTUALBOX_MEM_SIZE} =~ ^[0-9]*$ ]]  || common::error "vagrant memory is not numeric"
  [[ ${VAGRANT_VIRTUALBOX_EXTRA_DISK_GB} =~ ^[0-9]*$ ]]  || common::error "vagrant disk size is not numeric"
  [[ ${VAGRANT_DEVELOPER_REPOS,,} =~ ^((yes)|(no))$ ]] || common::error "VAGRANT_DEVELOPER_REPOS must be Yes or No"
  [[ -z "${VAGRANT_GUEST_ADDITIONS_URL}" ]] && common::error "missing VirtualBox GA ISO URL"
  [[ ${VAGRANT_GUEST_ADDITIONS_URL%%:*} =~ ^((https?)|(file))$ ]] || common::error "invalid VirtualBox GA ISO URL: ${VAGRANT_GUEST_ADDITIONS_URL}"
  [[ -z "${VAGRANT_GUEST_ADDITIONS_SHA256}" ]] && common::error "missing VirtualBox GA ISO checksum"
  [[ ${#VAGRANT_GUEST_ADDITIONS_SHA256} -eq 64  ]] || common::error "VAGRANT_GUEST_ADDITIONS_SHA256 must be SHA256"
  readonly VAGRANT_GUEST_ADDITIONS_URL VAGRANT_GUEST_ADDITIONS_SHA256
  # Retriece GA during validation to "fail fast"
  declare -g VAGRANT_GUEST_ADDITIONS_PATH
  common::retrieve_iso "${VAGRANT_GUEST_ADDITIONS_URL}" "${VAGRANT_GUEST_ADDITIONS_SHA256}" VAGRANT_GUEST_ADDITIONS_PATH
  readonly VAGRANT_GUEST_ADDITIONS_PATH
}

#######################################
# virt-customize arguments
# Globals:
#   VAGRANT_GUEST_ADDITIONS_PATH
#   VAGRANT_GUEST_ADDITIONS_SHA256
#   VAGRANT_GUEST_ADDITIONS_URL
# Arguments:
#   virt-customize argument nameref
# Returns:
#   None
#######################################
cloud::customize_args() {
  declare -n customize_args="$1"
  if [[ -n "${VAGRANT_GUEST_ADDITIONS_URL}" && -n "${VAGRANT_GUEST_ADDITIONS_SHA256}" ]]; then
    local iso_path
    iso_path=$(realpath "${VAGRANT_GUEST_ADDITIONS_PATH}")
    customize_args+=( --attach "${iso_path}" )
  fi
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
#   CLOUD, CLOUD_DIR
#   ORACLE_RELEASE
#   VAGRANT_VIRTUALBOX_CPU, VAGRANT_VIRTUALBOX_MEM_SIZE,
#   CPU_NUM, MEM_SIZE
#   VAGRANT_VIRTUALBOX_EXTRA_DISK_GB
#   VM_NAME, WORKSPACE
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::image_package() {
  local mk_envelope="${CLOUD_DIR}/${CLOUD}/mk-envelope.py"
  local cpu="${VAGRANT_VIRTUALBOX_CPU_NUM:-$CPU_NUM}"
  local memory="${VAGRANT_VIRTUALBOX_MEM_SIZE:-$MEM_SIZE}"
  local -a extra_disk=()
  local -a file_list=(
    ./Vagrantfile
    ./box-disk001.vmdk
    ./box.ovf
    ./metadata.json
  )

  common::convert_to_vmdk "${WORKSPACE}/${VM_NAME}/box-disk001.vmdk"
  if [[ -n ${VAGRANT_VIRTUALBOX_EXTRA_DISK_GB} ]]; then
    qemu-img create -f vmdk "${WORKSPACE}/${VM_NAME}/box-disk002.vmdk" "${VAGRANT_VIRTUALBOX_EXTRA_DISK_GB}G"
    extra_disk=( --extra-image "${WORKSPACE}/${VM_NAME}/box-disk002.vmdk" --extra-size "${VAGRANT_VIRTUALBOX_EXTRA_DISK_GB}")
    file_list+=(./box-disk002.vmdk)
  fi

  ${mk_envelope} --name "${VM_NAME}" --cpu "${cpu}" --memory "${memory}" \
    --image "${WORKSPACE}/${VM_NAME}/box-disk001.vmdk" --size "${DISK_SIZE_GB}" \
    "${extra_disk[@]}" > "${WORKSPACE}/${VM_NAME}/box.ovf"
  
  # Fix vmdk header
  local disk_uuid
  disk_uuid=$(grep '"vmdisk1"' "${WORKSPACE}/${VM_NAME}/box.ovf" | sed -e 's!.*vbox:uuid="\([^"]*\)".*!\1!')
  common::fix_vmdk_header "${WORKSPACE}/${VM_NAME}/box-disk001.vmdk" "${disk_uuid}"
  if [[ -n ${VAGRANT_VIRTUALBOX_EXTRA_DISK_GB} ]]; then
    disk_uuid=$(grep '"vmdisk2"' "${WORKSPACE}/${VM_NAME}/box.ovf" | sed -e 's!.*vbox:uuid="\([^"]*\)".*!\1!')
    common::fix_vmdk_header "${WORKSPACE}/${VM_NAME}/box-disk002.vmdk" "${disk_uuid}"
  fi

  cat > "${WORKSPACE}/${VM_NAME}/Vagrantfile" <<-EOF
		Vagrant::Config.run do |config|
		  # This Vagrantfile is auto-generated to contain the MAC address of the box.
		  # Custom configuration should be placed in the actual \`Vagrantfile\` in this box.
		  config.vm.base_mac = "080027D25971"
		end
	EOF

  if [[ "${ORACLE_RELEASE}" =~ ^[89]$ ]]; then
    # For the latest uek kernels (UEK7) we install kernel-uek-core which only has virtio drivers...
    mkdir "${WORKSPACE}/${VM_NAME}/include"
    cat > "${WORKSPACE}/${VM_NAME}/include/_Vagrantfile" <<-EOF
			Vagrant.configure("2") do |config|
			  config.vm.provider :virtualbox do |v|
			    v.default_nic_type = "virtio"
			  end
			end
		EOF
    file_list+=(./include)
  fi

  echo -n '{"provider":"virtualbox"}' >"${WORKSPACE}/${VM_NAME}/metadata.json"

  tar czvf "${WORKSPACE}/${VM_NAME}/${VM_NAME}.box" \
    -C "${WORKSPACE}/${VM_NAME}" \
    --remove-files \
    "${file_list[@]}"

}
