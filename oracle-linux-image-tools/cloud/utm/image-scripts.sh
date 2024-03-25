#!/usr/bin/env bash
#
# Cleanup and package image for the "None" image
#
# Copyright (c) 2022, 2024 Oracle and/or its affiliates.
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
#   OPC_PASSWORD
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::validate() {
  [[ -z "${OPC_PASSWORD}" ]] && common::error "missing OPC_PASSWORD"
  readonly OPC_PASSWORD
}

#######################################
# Image packaging: 
#   For VistualBox we convert back to VMDK and re-create the OVA file
#   For qemu we convert to a qcow2 file
# Globals:
#   CLOUD, CLOUD_DIR, VM_NAME
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::image_package() {
  local utm_dir uuid
  utm_dir="${VM_NAME}.utm"
  pushd "${WORKSPACE}/${VM_NAME}" || common::error "can't cd to image directory"
  mkdir -p "${utm_dir}/Images"
  mv "${VM_NAME}.qcow2" "${utm_dir}/Images/${VM_NAME}.qcow2"
  cp "${CLOUD_DIR}/${CLOUD}/Penguin.png" "${utm_dir}"
  uuid=$(python3 -c "import uuid; print(str(uuid.uuid4()).upper())")
  sed \
    -e "s/image.qcow2/${VM_NAME}.qcow2/" \
    -e "s!opc/opc!opc/${OPC_PASSWORD}!" \
    -e "s/00000000-0000-0000-0000-000000000000/${uuid}/" \
    "${CLOUD_DIR}/${CLOUD}/config.plist" > "${utm_dir}/config.plist"
  zip -r "${utm_dir}.zip" "${utm_dir}"
  rm -rf "${utm_dir}"
  popd || common::error "can't pop directory"
}
