#!/usr/bin/env bash
# shellcheck disable=SC1090
#
# Main provisioning script
#
# Copyright (c) 2019, 2024 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# Description:
#   - provision image by calling child provisioners
#   - Seal image by calling distribution seal function (final cleanup
#     cleanup before packaging)
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

set -e

# Constants
readonly PROVISION_DIR="/tmp/provision.d"
readonly ENV_FILE="${PROVISION_DIR}/env.properties"
# shellcheck disable=SC2034
readonly YUM_VERBOSE="-d1"

#######################################
# Load environment variables and provisioning scripts
# Globals:
#   ENV_FILE, PROVISION_DIR, PROXY_URL
#   Loaded environment files...
# Arguments:
#   None
# Returns:
#   None
#######################################
load_env() {
  local dir

  if [[ -r "${ENV_FILE}" ]]; then
    source "${ENV_FILE}"
  fi

  if [[ -n "${PROXY_URL}" ]]; then
    export http_proxy="${PROXY_URL}"
    export ftp_proxy="${PROXY_URL}"
    export https_proxy="${PROXY_URL}"
    export sftp_proxy="${PROXY_URL}"
  fi

  for dir in distr cloud cloud/distr custom; do
    if [[ -r "${PROVISION_DIR}/${dir}/provision.sh" ]]; then
      source "${PROVISION_DIR}/${dir}/provision.sh"
    fi
  done
}

#######################################
# provision
#######################################
provision () {
  common::echo_header "Load environment"
  load_env
  if [[ "$(type -t distr::provision)" = 'function' ]]; then
    common::echo_header "Run distribution provisioner"
    distr::provision
  fi
  if [[ "$(type -t cloud::provision)" = 'function' ]]; then
    common::echo_header "Run cloud provisioner"
    cloud::provision
  fi
  if [[ "$(type -t cloud_distr::provision)" = 'function' ]]; then
    common::echo_header "Run cloud distribution provisioner"
    cloud_distr::provision
  fi
  if [[ "$(type -t custom::provision)" = 'function' ]]; then
    common::echo_header "Run custom provisioner"
    custom::provision
  fi
  if [[ "$(type -t custom::cleanup)" = 'function' ]]; then
    common::echo_header "Run custom cleanup"
    custom::cleanup
  fi
  if [[ "$(type -t cloud_distr::cleanup)" = 'function' ]]; then
    common::echo_header "Run cloud distribution cleanup"
    cloud_distr::cleanup
  fi
  if [[ "$(type -t cloud::cleanup)" = 'function' ]]; then
    common::echo_header "Run cloud cleanup"
    cloud::cleanup
  fi
  if [[ "$(type -t distr::cleanup)" = 'function' ]]; then
    common::echo_header "Run distribution cleanup"
    distr::cleanup
  fi
}

#######################################
# Main
#######################################
main () {
  source "${PROVISION_DIR}/provision-common.sh"
  provision
}

main "$@"
