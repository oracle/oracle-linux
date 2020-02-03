#!/usr/bin/env bash
#
# Cleanup and package image for OLVM
#
# Copyright (c) 1982-2020 Oracle and/or its affiliates. All rights reserved.
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
  local mk_envelope="${CLOUD_DIR}/${CLOUD}/mk-envelope.py"
  # Decompose Build Name into Release/update/platform
  local build_rel="${DISTR_NAME%U*}"
  local build_upd="${DISTR_NAME#*U}"
  local build_upd="${build_upd%%_*}"
  local build_platform="${DISTR_NAME#*_}"

  qemu-img convert -c -O qcow2 System.img System.qcow
  rm System.img

  ${mk_envelope} \
    -r "${build_rel}" \
    -u "${build_upd##U}" \
    -v "${BUILD_NUMBER}" \
    -s "${DISK_SIZE_GB}" \
    -i System.qcow \
    -c "${CPU_NUM}" \
    -m "${MEM_SIZE}"
}
