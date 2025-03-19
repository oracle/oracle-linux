#!/usr/bin/env bash
#
# Cleanup and package image for OVM
#
# Copyright (c) 2019, 2025 Oracle and/or its affiliates.
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
# Image packaging - creates a PVM and PVHVM OVA
# Globals:
#   CLOUD, CLOUD_DIR, DISK_SIZE_GB, DISTR_NAME, IMAGE_VERSION, VM_NAME
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::image_package() {
  common::convert_to_vmdk "${WORKSPACE}/${VM_NAME}/System.vmdk"

  # Decompose Build Name into Release/update/platform
  local build_rel="${DISTR_NAME%U*}"
  local build_upd="${DISTR_NAME#*U}"
  local build_upd="${build_upd%%_*}"

  pushd "${WORKSPACE}/${VM_NAME}" || common::error "can't cd to image directory"
  "${CLOUD_DIR}/${CLOUD}/mk-envelope.sh" \
    -r "${build_rel}" \
    -u "${build_upd##U}" \
    -v "${IMAGE_VERSION}" \
    -s "${DISK_SIZE_GB}" \
    > "${VM_NAME}.ovf"

  common::make_manifest "${VM_NAME}.ovf" System.vmdk >"${VM_NAME}.mf"
  common::make_ova "${VM_NAME}.ovf" "${VM_NAME}.mf" System.vmdk
  popd || common::error "can't pop directory"
}
