#!/usr/bin/env bash
#
# Cleanup and package image for OLVM
#
# Copyright (c) 2020, 2022 Oracle and/or its affiliates.
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
#   OLVM_TEMPLATE
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::validate() {
  [[ "${OLVM_TEMPLATE,,}" =~ ^(yes)|(no)$  ]]  || error "OLVM_TEMPLATE must be Yes or No"
  readonly OLVM_TEMPLATE
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
# Image packaging - creates an OVA
# Globals:
#   CLOUD_DIR CLOUD DISTR_NAME OLVM_TEMPLATE
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
  local extra_args=()
  local package_filename vmdk

  common::convert_to_qcow2 System.qcow

  if [[ "${OLVM_TEMPLATE,,}" = "yes" ]]; then
    extra_args+=("--template")
    package_filename="template"
  else
    package_filename="vm"
  fi

  if [[ -n "${CUSTOM_SCRIPT}" ]]; then
    extra_args+=("--script" "${CUSTOM_SCRIPT}")
  fi

  ${mk_envelope} "${extra_args[@]}" \
    -r "${build_rel}" \
    -u "${build_upd##U}" \
    -v "${BUILD_NUMBER}" \
    -s "${DISK_SIZE_GB}" \
    -i System.qcow \
    -c "${CPU_NUM}" \
    -m "${MEM_SIZE}" \
    >"${package_filename}.ovf"

  vmdk=$(grep "ovf:href" "${package_filename}.ovf" | sed -r -e 's/.*ovf:href="([^"]+)".*/\1/')

  mv System.qcow "${vmdk}"

  common::make_ova "${package_filename}.ovf" "${vmdk}"
}
