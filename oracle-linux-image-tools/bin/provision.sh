#!/usr/bin/env bash
# shellcheck disable=SC1090
#
# Packer main provisioning script
#
# Copyright (c) 2019, 2022 Oracle and/or its affiliates.
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
readonly PACKER_FILES="/tmp/packer_files"
readonly ENV_FILE="${PACKER_FILES}/env.properties"
# shellcheck disable=SC2034
readonly YUM_VERBOSE="-d1"

#######################################
# Echo header / message convenience functions
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
echo_header() {
  echo "=== $* ==="
}

echo_message() {
  echo "--- $* ---"
}

echo_error() {
  echo "--- $* ---" >&2
  exit 1
}

#######################################
# Load environment variables and provisioning scripts
# Globals:
#   ENV_FILE
#   PACKER_FILES
#   PROXY_URL
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

  for dir in \
    "${PACKER_FILES}/distr" \
    "${PACKER_FILES}/cloud" \
    "${PACKER_FILES}/cloud/distr" \
    "${PACKER_FILES}/custom"
  do
    if [[ -r "${dir}/provision.sh" ]]; then
      source "${dir}/provision.sh"
    fi
  done
}

#######################################
# provision
#######################################
provision () {
  echo_header "Load environment"
  load_env
  if [[ "$(type -t distr::provision)" = 'function' ]]; then
    echo_header "Run distribution provisioner"
    distr::provision
  fi
  if [[ "$(type -t cloud::provision)" = 'function' ]]; then
    echo_header "Run cloud provisioner"
    cloud::provision
  fi
  if [[ "$(type -t cloud_distr::provision)" = 'function' ]]; then
    echo_header "Run cloud distribution provisioner"
    cloud_distr::provision
  fi
  if [[ "$(type -t custom::provision)" = 'function' ]]; then
    echo_header "Run custom provisioner"
    custom::provision
  fi
  if [[ "$(type -t custom::cleanup)" = 'function' ]]; then
    echo_header "Run custom cleanup"
    custom::cleanup
  fi
  if [[ "$(type -t cloud_distr::cleanup)" = 'function' ]]; then
    echo_header "Run cloud distribution cleanup"
    cloud_distr::cleanup
  fi
  if [[ "$(type -t cloud::cleanup)" = 'function' ]]; then
    echo_header "Run cloud cleanup"
    cloud::cleanup
  fi
  if [[ "$(type -t distr::cleanup)" = 'function' ]]; then
    echo_header "Run distribution cleanup"
    distr::cleanup
  fi
}

#######################################
# seal
#######################################
seal () {
  echo_header "Load environment"
  load_env
  if [[ "$(type -t distr::seal)" = 'function' ]]; then
    echo_header "Seal VM image"
    distr::seal
  else
    echo_message "No seal function defined"
  fi
}

#######################################
# Main
#######################################
main () {
  if [[ -z ${OLIT_ACTION} ]]; then
    echo_error "OLIT_ACTION undefined"
  fi
  case "${OLIT_ACTION}" in
    provision)
      provision
      ;;
    seal)
      seal
      ;;
    *)
      echo_error "Unexpected action: ${OLIT_ACTION}"
      ;;
  esac
}

main "$@"
