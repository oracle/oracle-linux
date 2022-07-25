#!/usr/bin/env bash
#
# Cleanup and package image for the "None" image
#
# Copyright (c) 2019, 2022 Oracle and/or its affiliates.
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
# Image packaging: 
#   For VistualBox we convert back to VMDK and re-create the OVA file
#   For qemu we convert to a qcow2 file
# Globals:
#   PACKER_BUILDER
#   VM_NAME
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::image_package() {
  if common::is_vbox ; then
    local vmdk
    vmdk=$(grep "ovf:href" "${VM_NAME}.ovf" | sed -r -e 's/.*ovf:href="([^"]+)".*/\1/')
    common::convert_to_vmdk "${vmdk}"
    common::make_manifest "${VM_NAME}.ovf" "${vmdk}" > "${VM_NAME}.mf"
    common::make_ova "${VM_NAME}.ovf" "${VM_NAME}.mf" "${vmdk}"
  else
    common::convert_to_qcow2 "${VM_NAME}.qcow"
  fi
}
