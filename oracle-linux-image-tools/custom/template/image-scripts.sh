#!/usr/bin/env bash
#
# image scripts template for custom projects
#
# Description: this module provides the following functions which are run on
# the host:
#   custom::validate: called at the very begining to validate project paramters
#   custom::kickstart: allow changes in the kickstart file
#   custom::packer_conf: allow changes in the packer configuration file
#   custom::image_cleanup: image cleanup actions after build completes
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
  echo_message "Running ${FUNCNAME[0]}"
  # [[ "${CUSTOM_YES_NO_PARAMETER,,}" =~ ^(yes)|(no)$ ]] || error "CUSTOM_YES_NO_PARAMETER must be yes or no"
  # readonly CUSTOM_YES_NO_PARAMETER
}

#######################################
# Kickcstart fixup
# Globals:
#   All build parameters are available
# Arguments:
#   kickstart file name
# Returns:
#   None
#######################################
custom::kickstart() {
  echo_message "Running ${FUNCNAME[0]}"
  # local ks_file="$1"
  # Use `sed` to modify the kickstart file
}

#######################################
# Packer configuration
# Globals:
#   All build parameters are available
# Arguments:
#   Packer configuration file
# Returns:
#   None
#######################################
custom::packer_conf() {
  echo_message "Running ${FUNCNAME[0]}"
  # local packer_file="$1"
  # Use `sed` to modify the packer configuration file
}

#######################################
# Cleanup actions run directly on the image
# Globals:
#   All build parameters are available
# Arguments:
#   root filesystem directory
#   boot filesystem directory
# Returns:
#   None
#######################################
custom::image_cleanup() {
  local root_fs="$1"
  local boot_fs="$2"

  echo_message "Running ${FUNCNAME[0]}"

  # Ensure we don't blindly cleanup local host!
  [[ -z ${root_fs} ]] && error "Undefined root filesystem"
  [[ -z ${boot_fs} ]] && error "Undefined boot filesystem"

  # Cleanup actions -- use `chroot` to execute actions in the context of
  # the image.
  # See examples in distr image-scripts.sh files
}

#######################################
# Image packaging
#   Warning: when this function is defined it will orverride the cloud
#   image_package fuction!
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
#   if common::is_vbox ; then
#     # VirtualBox Packer builder
#     :
#   else
#     # QEmu Packer builder
#     :
#   fi
# }
