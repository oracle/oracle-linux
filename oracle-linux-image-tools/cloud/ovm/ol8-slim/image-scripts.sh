#!/usr/bin/env bash
#
# Validate parameters
#
# Copyright (c) 2021 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# Description: this module provides:
#   cloud_distr::validate: parameter validation
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

#######################################
# Parameter validation
# Globals:
#   EXTRA_KERNEL
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud_distr::validate() {
  [[ "${EXTRA_KERNEL,,}" =~ ^(yes)|(no)$ ]] || error "EXTRA_KERNEL must be yes or no"
  readonly EXTRA_KERNEL
}
