#!/usr/bin/env bash
#
# image scripts template for custom projects
#
# Description: this module provides the following functions which are run on
# the host:
#   custom::validate: called at the very beginning to validate project parameters
#   custom::kickstart: allow changes in the kickstart file
#   custom::customize_args: arguments to pass to virt-customize (optional)
#   custom::image_package: package image in final format (override the cloud
#     image_package function!)
# All functions are optional
#

#######################################
# Validate custom project parameters
# Call `error` function to raise an error
# Globals:
#   All build parameters are available
# Arguments:
#   None
# Returns:
#   None
#######################################
custom::validate() {
  common::echo_message "Running ${FUNCNAME[0]}"
  # [[ "${CUSTOM_YES_NO_PARAMETER,,}" =~ ^((yes)|(no))$ ]] || common::error "CUSTOM_YES_NO_PARAMETER must be yes or no"
  # readonly CUSTOM_YES_NO_PARAMETER
}

#######################################
# Kickstart fixup
# Globals:
#   All build parameters are available
# Arguments:
#   kickstart file name
# Returns:
#   None
#######################################
custom::kickstart() {
  common::echo_message "Running ${FUNCNAME[0]}"
  # local ks_file="$1"
  # Use `sed` to modify the kickstart file
}

#######################################
# Image packaging
#   Warning: when this function is defined it will override the cloud
#   image_package function!
#   You most probably do not need to implement this function.
#   See cloud image_package function for examples.
# Globals:
#   All build parameters are available
# Arguments:
#   None
# Returns:
#   None
#######################################
# custom::image_package() {
#   :
# }
