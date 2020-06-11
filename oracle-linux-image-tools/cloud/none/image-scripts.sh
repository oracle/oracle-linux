#!/usr/bin/env bash
#
# Cleanup and package image for the "None" image
#
# Copyright (c) 2019 Oracle and/or its affiliates.
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
cloud::image_cleanup() {
  :
}

#######################################
# Image packaging: We convert back to VMDK and re-create the OVA file
# Globals:
#   VM_NAME
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::image_package() {
  local vmdk=$(grep "ovf:href" "${VM_NAME}.ovf" | sed -r -e 's/.*ovf:href="([^"]+)".*/\1/')
  vboxmanage convertfromraw System.img --format VMDK "${vmdk}" --variant Stream
  rm System.img
  tar cvf "${VM_NAME}.ova" "${VM_NAME}.ovf" "${vmdk}"
  rm "${vmdk}"
}
