#!/usr/bin/env bash
#
# Cleanup and package image for OCI
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
#     This function must be defined either at cloud or cloud/distribution level#
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
  [[ "${OCI_REPO_MAPPER,,}" =~ ^((yes)|(no))$  ]]  || common::error "OCI_REPO_MAPPER must be Yes or No"
  readonly OCI_REPO_MAPPER
}

#######################################
# Image packaging - nothing needs to be done
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::image_package() {
  # We only need a QCOW2 file
  :
}
