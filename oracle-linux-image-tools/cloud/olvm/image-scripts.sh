#!/usr/bin/env bash
#
# Cleanup and package image for OLVM
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
#   OLVM_TEMPLATE
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::validate() {
  [[ "${OLVM_TEMPLATE,,}" =~ ^((yes)|(no))$  ]]  || common::error "OLVM_TEMPLATE must be Yes or No"
  readonly OLVM_TEMPLATE
}

#######################################
# Image packaging - creates an OVA
# Globals:
#   BUILD_NUMBER, CLOUD, CLOUD_DIR, CPU_NUM, CUSTOM_SCRIPT, DISK_SIZE_GB, DISTR_NAME
#   MEM_SIZE, OLVM_TEMPLATE, VM_NAME
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
  local package_filename href

  if [[ "${OLVM_TEMPLATE,,}" = "yes" ]]; then
    extra_args+=("--template")
    package_filename="template"
  else
    package_filename="vm"
  fi

  if [[ -n "${CUSTOM_SCRIPT}" ]]; then
    extra_args+=("--script" "${CUSTOM_SCRIPT}")
  fi

  pushd "${WORKSPACE}/${VM_NAME}" || common::error "can't cd to image directory"
  ${mk_envelope} "${extra_args[@]}" \
    -r "${build_rel}" \
    -u "${build_upd##U}" \
    -v "${BUILD_NUMBER}" \
    -s "${DISK_SIZE_GB}" \
    -i "${VM_NAME}.qcow2" \
    -c "${CPU_NUM%%,*}" \
    -m "${MEM_SIZE}" \
    >"${package_filename}.ovf"

  href=$(grep "ovf:href" "${package_filename}.ovf" | sed -r -e 's/.*ovf:href="([^"]+)".*/\1/')

  mv "${VM_NAME}.qcow2" "${href}"

  common::make_ova "${package_filename}.ovf" "${href}"

  popd || common::error "can't pop directory"
}
