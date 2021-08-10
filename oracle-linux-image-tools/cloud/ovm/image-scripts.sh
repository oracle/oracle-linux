#!/usr/bin/env bash
#
# Cleanup and package image for OVM
#
# Copyright (c) 2019,2020 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# Description: this module provides 3 functions:
#   cloud::validate: optional parameter validation
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
#   ORACLE_RELEASE
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::validate() {
  :
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
# Image packaging - creates a PVM and PVHVM OVA
# Globals:
#   CLOUD_DIR CLOUD DISTR_NAME IMAGE_VERSION
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::image_package() {
  local mk_envelope="${CLOUD_DIR}/${CLOUD}/mk-envelope.sh"
  # Decompose Build Name into Release/update/platform
  local build_rel="${DISTR_NAME%U*}"
  local build_upd="${DISTR_NAME#*U}"
  local build_upd="${build_upd%%_*}"

  qemu-img convert -f raw -O vmdk -o subformat=streamOptimized System.img System.vmdk
  rm System.img

  ${mk_envelope} \
    -r "${build_rel}" \
    -u "${build_upd##U}" \
    -v "${IMAGE_VERSION}" \
    -s "${DISK_SIZE_GB}"

  rm System.vmdk
}
