#!/usr/bin/env bash
#
# Cleanup and package image for the "None" image
#
# Copyright (c) 2019, 2024 Oracle and/or its affiliates.
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
# Image packaging: do nothing
# (Provide stub as we need a packaging fnction)
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::image_package() {
  :
}
