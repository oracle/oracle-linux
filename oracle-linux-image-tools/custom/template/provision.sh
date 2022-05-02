#!/usr/bin/env bash
#
# Packer provisioning script template for custom projects
#
# Description: provision an custom image. This module provides 2 functions,
# which are run inside the VM:
#   custom::provision: provision the instance
#   custom::cleanup: instance cleanup before shutdown
# Both functions are optional.
#

#######################################
# Provisioning
# Globals:
#   All build parameters are available
# Arguments:
#   None
# Returns:
#   None
#######################################
custom::provision() {
  echo_message "Running ${FUNCNAME[0]} for ${PROJECT_NAME} (${DISTR}/${CLOUD})"
  cat /tmp/packer_files/custom/custom.txt
}

#######################################
# Cleanup
# Globals:
#   All build parameters are available
# Arguments:
#   None
# Returns:
#   None
#######################################
custom::cleanup() {
  echo_message "Running ${FUNCNAME[0]}"
}
