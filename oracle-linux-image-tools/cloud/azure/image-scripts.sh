#!/usr/bin/env bash
#
# Cleanup and package image for Azure
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
# Image packaging
# Globals:
#   VM_NAME
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::image_package() {
  common::convert_to_vhd "${VM_NAME}.vhd"
}
