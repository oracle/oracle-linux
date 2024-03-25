#!/usr/bin/env bash
# shellcheck disable=SC1090
#
# Create minimal Oracle Linux images
#
# Copyright (c) 2019, 2024 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# Description: creates minimal Oracle Linux images which can be used in cloud
# environment.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

# Constants
PGM=$(basename "$0")
BIN_DIR=$( cd "$(dirname "$0")" ; pwd -P )
REPO_DIR=$(dirname "${BIN_DIR}")
readonly PGM BIN_DIR REPO_DIR
readonly DISTR_DIR="${REPO_DIR}/distr"
readonly CLOUD_DIR="${REPO_DIR}/cloud"
readonly CUSTOM_DIR="${REPO_DIR}/custom"
readonly ENV_FILE="env.properties"
readonly ENV_FILE_DEFAULTS="${REPO_DIR}/${ENV_FILE}.defaults"
readonly FILES_DIR="files"
readonly PROVISION_DIR="provision.d"
readonly PROVISION_SCRIPT="provision.sh"
readonly IMAGE_SCRIPTS="image-scripts.sh"

# Exit on error
set -e

#######################################
# Print usage message and exit
# Globals:
#   ENV_FILE, PGM, REPO_DIR
# Arguments:
#   None
# Returns:
#   None
#######################################
usage() {
  echo "Usage: ${PGM} [--env ENV_FILE]"
  echo -e "\tGenerate image based on ENV_FILE"
  echo -e "\tDefault ENV_FILE is ${REPO_DIR}/${ENV_FILE}"
  exit 1
}

#######################################
# Parse arguments
# Exit on error.
# Globals:
#   ENV_FILE, LOCAL_ENV_FILE, REPO_DIR
# Arguments:
#   Command line
# Returns:
#   None
#######################################
parse_args() {
  common::echo_header "Parse arguments"

  LOCAL_ENV_FILE="${REPO_DIR}/${ENV_FILE}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      "--env"|"-e")
      	if [[ $# -lt 2 ]]; then
      	  echo "Missing parameter" >&2
      	  usage
      	fi
      	LOCAL_ENV_FILE="$2"
      	shift; shift
      	;;
      "--help"|"-h")
      	usage
      	;;
      *)
      	echo "Invalid parameter" >&2
      	usage
      	;;
    esac
  done

  readonly LOCAL_ENV_FILE
}

#######################################
# Load environment variables
# Globals:
#   CLOUD, CLOUD_DIR, CUSTOM, CUSTOM_DIR, DISTR, DISTR_DIR, ENV_FILES
#   ENV_FILE_DEFAULTS, LOCAL_ENV_FILE, WORKSPACE
#   Loaded environment files...
# Arguments:
#   None
# Returns:
#   None
#######################################
load_env() {
  common::echo_header "Load environment"

  [[ -e "${ENV_FILE_DEFAULTS}" ]] ||
    common::error "missing default env file '${ENV_FILE_DEFAULTS}'"
  source "${ENV_FILE_DEFAULTS}"

  [[ -e "${LOCAL_ENV_FILE}" ]] ||
    common::error "env file '${LOCAL_ENV_FILE}' does not exists"
  source "${LOCAL_ENV_FILE}"

  # Check for minimal environment
  [[ -z "${WORKSPACE}" ]] && common::error "no workspace directory defined"
  [[ -d "${WORKSPACE}" ]] ||
    common::error "workspace directory '${WORKSPACE}' does not exist"
  [[ -z "${DISTR}" ]] && common::error "no distribution defined"
  [[ -d "${DISTR_DIR}/${DISTR}" ]] || common::error "no such distribution: ${DISTR}"
  [[ -z "${CLOUD}" ]] && common::error "no cloud defined"
  [[ -d "${CLOUD_DIR}/${CLOUD}" ]] || common::error "no such cloud: ${CLOUD}"
  [[ -z "${CUSTOM}" ]] && 
    common::error "no custom project defined (use 'none' for no customization)"
  [[ "${CUSTOM}" == "none" || -d "${CUSTOM_DIR}/${CUSTOM}" ]] || 
    common::error "no such custom project: ${CUSTOM}"

  # Load all environment files
  # LOCAL_ENV_FILE is re-loaded as it overrides all defaults
  local env_file
  declare -ag ENV_FILES
  ENV_FILES=(
    "${ENV_FILE_DEFAULTS}"
    "${DISTR_DIR}/${DISTR}/${ENV_FILE}"
    "${CLOUD_DIR}/${CLOUD}/${ENV_FILE}"
    "${CLOUD_DIR}/${CLOUD}/${DISTR}/${ENV_FILE}"
    "${CUSTOM_DIR}/${CUSTOM}/${ENV_FILE}"
    "${LOCAL_ENV_FILE}"
  )
  readonly ENV_FILES
  for env_file in "${ENV_FILES[@]}"; do
    [[ -r "${env_file}" ]] && source "${env_file}"
  done

  readonly WORKSPACE DISTR CLOUD CUSTOM

  # Basic validation
  [[ -z "${ISO_URL}" ]] && common::error "missing ISO URL"
  [[ ${ISO_URL%%:*} =~ ^((https?)|(file))$ ]] || common::error "invalid ISO URL: ${ISO_URL}"
  [[ -z "${ISO_CHECKSUM}" ]] && common::error "missing ISO checksum"
  [[ ${#ISO_CHECKSUM} -eq 40 || ${#ISO_CHECKSUM} -eq 64  ]] ||
    common::error "ISO_CHECKSUM must be SHA1 or SHA256"
  readonly ISO_URL ISO_CHECKSUM

  [[ ${ROOT_PASSWORD} =~ ^((file:)|(password:)|(locked)) ]] ||
    common::error "invalid root password selector: ${ROOT_PASSWORD}"
  [[ -z ${ROOT_SSH_KEY} || ${ROOT_SSH_KEY} =~ ^((file:)|(string:)) ]] ||
    common::error "invalid root ssh key selector: ${ROOT_SSH_KEY}"
  [[ ${PERMIT_ROOT_LOGIN,,} =~ ^((yes)|(prohibit-password)|(forced-commands-only)|(no))$ ]] ||
    common::error "invalid root login selector: ${PERMIT_ROOT_LOGIN}"
  readonly ROOT_PASSWORD ROOT_SSH_KEY PERMIT_ROOT_LOGIN

  # Attempt to derive DISTR_NAME from the iso image name, otherwise fall back
  # to the configured name
  local distr_name
  # Note: OL7 media have space in the label which needs to be escaped
  # shellcheck disable=SC2001
  distr_name=$(sed -e 's/^.*OracleLinux-R\([[:digit:]]\)-U\([[:digit:]]\+\)\(-Server\)\?-\([^-]\+\)\(-dvd\)\?\(-[[:digit:]]\+\)\?\.iso$/OL\1U\2_\4/' <<< "${ISO_URL}")
  if [[ $distr_name =~ ^OL[6789]U ]]; then
    DISTR_NAME="${distr_name}"
  fi

  [[ -z "${DISTR_NAME}" && -z "${BUILD_NUMBER}" ]] &&
    common::error "missing distribution name / build number"
  if [[ -z "${VM_NAME}" ]]; then
    VM_NAME="${DISTR_NAME}-${CLOUD}-b${BUILD_NUMBER}"
  fi
  KS_FILE="${VM_NAME}-ks.cfg"
  readonly DISTR_NAME BUILD_NUMBER VM_NAME

  [[ -e "${WORKSPACE}/${VM_NAME}" ]] &&
    common::error "${WORKSPACE}/${VM_NAME} already exists"

  [[ ${DISK_SIZE_GB} =~ ^[0-9]+$ ]] || common::error "disk size is not numeric"
  readonly DISK_SIZE_GB

  [[ ${INSTALL_WAIT_TIME} =~ ^[0-9]+$ ]] || common::error "install wait time is not numeric"
  readonly INSTALL_WAIT_TIME

  [[ "${SETUP_SWAP,,}" =~ ^((yes)|(no))$ ]] || common::error "SETUP_SWAP must be yes or no"
  readonly SETUP_SWAP

  [[ "${SELINUX,,}" =~ ^((enforcing)|(permissive)|(disabled))$ ]] || common::error "SELINUX must be enforcing, permissive or disabled"
  readonly SELINUX

  [[ "${SERIAL_CONSOLE,,}" =~ ^((yes)|(no))$ ]] || common::error "SERIAL_CONSOLE must be yes or no"
  readonly SERIAL_CONSOLE

  [[ "${BOOT_MODE,,}" =~ ^((bios)|(uefi))$ ]] || common::error "BOOT_MODE must be bios or uefi"
  readonly BOOT_MODE

  if [[ -z ${OS_VARIANT} ]]; then
    OS_VARIANT=$(osinfo-query os --fields=short-id vendor="Oracle America" |
      grep "ol${ORACLE_RELEASE}\." |
      tail -1 |
      sed -e 's/ //g')
  fi
  [[ -z ${OS_VARIANT} ]] && common::error "can't determine OS_VARIANT; you must define it in your environment file"
  osinfo-query os --fields=short-id short-id="${OS_VARIANT}" >/dev/null || common::error "Invalid OS_VARIANT"
  readonly OS_VARIANT

  [[ -z ${CACHE_DIR} ]] && common::error "CACHE_DIR must be specified"
  ( cd "${WORKSPACE}" && [[ -d $(dirname "${CACHE_DIR}") ]] ) ||
    common::error "parent directory of CACHE_DIR must exists"
  CACHE_PATH="$(cd "${WORKSPACE}" && cd "$(dirname "${CACHE_DIR}")" && pwd -P)/$(basename "${CACHE_DIR}")"
  readonly CACHE_PATH

  # Source image scripts
  if [[ -r "${DISTR_DIR}/${DISTR}/${IMAGE_SCRIPTS}" ]]; then
    source "${DISTR_DIR}/${DISTR}/${IMAGE_SCRIPTS}"
  fi
  if [[ -r "${CLOUD_DIR}/${CLOUD}/${IMAGE_SCRIPTS}" ]]; then
    source "${CLOUD_DIR}/${CLOUD}/${IMAGE_SCRIPTS}"
  fi
  if [[ -r "${CLOUD_DIR}/${CLOUD}/${DISTR}/${IMAGE_SCRIPTS}" ]]; then
    source "${CLOUD_DIR}/${CLOUD}/${DISTR}/${IMAGE_SCRIPTS}"
  fi
  if [[ -r "${CUSTOM_DIR}/${CUSTOM}/${IMAGE_SCRIPTS}" ]]; then
    source "${CUSTOM_DIR}/${CUSTOM}/${IMAGE_SCRIPTS}"
  fi

  # Validate distr / cloud parameters
  if [[ "$(type -t distr::validate)" = 'function' ]]; then
    distr::validate
  fi
  if [[ "$(type -t cloud::validate)" = 'function' ]]; then
    cloud::validate
  fi
  if [[ "$(type -t cloud_distr::validate)" = 'function' ]]; then
    cloud_distr::validate
  fi
  if [[ "$(type -t custom::validate)" = 'function' ]]; then
    custom::validate
  fi
}

#######################################
# Stage required files for provisioning
# Globals:
#   CLOUD, CLOUD_DIR, CUSTOM, CUSTOM_DIR, DISTR, DISTR_DIR, ENV_FILES, FILES_DIR
#   GLOBAL_ENV_FILE, PROVISION_DIR, PROVISION_SCRIPT, VM_NAME, WORKSPACE
#   Loaded environment files...
# Arguments:
#   None
# Returns:
#   None
#######################################
stage_files() {
  common::echo_header "Stage provisioning files"

  local provision_path="${WORKSPACE}/${VM_NAME}/${PROVISION_DIR}"

  mkdir "${provision_path}"

  # Global environment file
  readonly GLOBAL_ENV_FILE="${provision_path}/${ENV_FILE}"
  for env_file in "${ENV_FILES[@]}"; do
    [[ -r "${env_file}" ]] && cat "${env_file}" >> "${GLOBAL_ENV_FILE}"
  done

  # Main provisionning script
  cp "${BIN_DIR}/provision.sh" "${provision_path}/"
  cp "${BIN_DIR}/provision-common.sh" "${provision_path}/"

  # Cloud files into cloud subdir
  mkdir -p "${provision_path}/cloud/distr"
  if [[ -d "${CLOUD_DIR}/${CLOUD}/${FILES_DIR}" ]]; then
    cp -RL "${CLOUD_DIR}/${CLOUD}/${FILES_DIR}/." "${provision_path}/cloud"
  fi
  if [[ -d "${CLOUD_DIR}/${CLOUD}/${DISTR}/${FILES_DIR}" ]]; then
    cp -RL "${CLOUD_DIR}/${CLOUD}/${DISTR}/${FILES_DIR}/." "${provision_path}/cloud/distr"
  fi
  # Distr files into distr subdir
  mkdir "${provision_path}/distr"
  if [[ -d "${DISTR_DIR}/${DISTR}/${FILES_DIR}" ]]; then
    cp -RL "${DISTR_DIR}/${DISTR}/${FILES_DIR}/." "${provision_path}/distr"
  fi
  # Custom files into custom subdir
  mkdir "${provision_path}/custom"
  if [[ -d "${CUSTOM_DIR}/${CUSTOM}/${FILES_DIR}" ]]; then
    cp -RL "${CUSTOM_DIR}/${CUSTOM}/${FILES_DIR}/." "${provision_path}/custom"
  fi

  # Provisioners
  if [[ -r "${CLOUD_DIR}/${CLOUD}/${PROVISION_SCRIPT}" ]]; then
    cp "${CLOUD_DIR}/${CLOUD}/${PROVISION_SCRIPT}" "${provision_path}/cloud/"
  fi
  if [[ -r "${CLOUD_DIR}/${CLOUD}/${DISTR}/${PROVISION_SCRIPT}" ]]; then
    cp "${CLOUD_DIR}/${CLOUD}/${DISTR}/${PROVISION_SCRIPT}" "${provision_path}/cloud/distr/"
  fi
  if [[ -r "${DISTR_DIR}/${DISTR}/${PROVISION_SCRIPT}" ]]; then
    cp "${DISTR_DIR}/${DISTR}/${PROVISION_SCRIPT}" "${provision_path}/distr/"
  fi
  if [[ -r "${CUSTOM_DIR}/${CUSTOM}/${PROVISION_SCRIPT}" ]]; then
    cp "${CUSTOM_DIR}/${CUSTOM}/${PROVISION_SCRIPT}" "${provision_path}/custom"
  fi
}

#######################################
# Stage kickstart file
# Globals:
#   DISTR, DISTR_DIR, KS_FILE, REPO, REPO_URL, SETUP_SWAP, VM_NAME, WORKSPACE
# Arguments:
#   None
# Returns:
#   None
#######################################
stage_kickstart() {
  common::echo_header "Stage kickstart file"

  local ks_path="${WORKSPACE}/${VM_NAME}/${KS_FILE}"

  cp "${DISTR_DIR}/${DISTR}/"*-ks.cfg "${ks_path}"

  if [[ "${SETUP_SWAP,,}" = "no" ]]; then
    sed -i -e '/^part swap /d' "${ks_path}"
  fi

  if [[ -n "${REPO_URL}" ]]; then
    sed -i -e \
      '/^# URL to an installation tree/a url --url "'"${REPO_URL}"'"' \
      "${ks_path}"
  fi

  local ks_repo
  for ks_repo in "${!REPO[@]}"; do
    sed -i -e \
      '/^# Additional yum repositories/a repo --name "'"${ks_repo}"'" --baseurl "'"${REPO[${ks_repo}]}"'"' \
      "${ks_path}"
  done

  # Kickstart fixups at distr / cloud_distr level
  if [[ "$(type -t distr::kickstart)" = 'function' ]]; then
    distr::kickstart "${ks_path}"
  fi
  if [[ "$(type -t cloud_distr::kickstart)" = 'function' ]]; then
    cloud_distr::kickstart "${ks_path}"
  fi
  if [[ "$(type -t custom::kickstart)" = 'function' ]]; then
    custom::kickstart "${ks_path}"
  fi
}

#######################################
# Create Oracle Linux image
# The outcome is a qcow2 file ${WORKSPACE}/${VM_NAME}/${VM_NAME}.qcow2 with
# OL installed based on the generated kickstart file.
# Globals:
# BOOT_COMMAND, BOOT_COMMAND_SERIAL_CONSOLE, BOOT_LOCATION, BOOT_MODE
# CPU_NUM, DISK_SIZE_MB, ISO_CHECKSUM, ISO_PATH, KS_FILE
# MEM_SIZE, SERIAL_CONSOLE, VM_NAME, WORKSPACE
# Arguments:
#   None
# Returns:
#   None
#######################################
image_create() {
  common::echo_header "Install Oracle Linux"

  # retrieve disk label -- alternatively: isoinfo -d -i
  local ISO_LABEL
  # shellcheck disable=SC2034,SC2153
  ISO_LABEL=$(file "${ISO_PATH}" | sed -e "s/.* '\(.*\)' .*/\1/"  -e 's/ /\\x20/g')

  declare -ga virt_install_args
  # Set Serial conole
  if [[ "${SERIAL_CONSOLE,,}" = "yes" ]]; then
    BOOT_COMMAND+=( "${BOOT_COMMAND_SERIAL_CONSOLE[@]}" )
  else
    virt_install_args+=(--wait "${INSTALL_WAIT_TIME}" --noautoconsole)
  fi

  if [[ ${BOOT_MODE,,} == uefi ]]; then
    virt_install_args+=(--boot uefi)
  fi

  # Dereference symlink as virt-instal/qemu don't like these
  local iso_path
  iso_path=$(realpath -e "${ISO_PATH}")

  local location
  if [[ -n ${BOOT_LOCATION} ]]; then
    location=",kernel=${BOOT_LOCATION}/vmlinuz,initrd=${BOOT_LOCATION}/initrd.img"
  fi

  # shellcheck disable=SC2294
 virt-install --os-type linux --os-variant "${OS_VARIANT}" --name "${VM_NAME}" \
    --cpus "${CPU_NUM}" --memory "${MEM_SIZE}" \
    --controller "scsi,model=virtio-scsi" \
    --disk "path=${WORKSPACE}/${VM_NAME}/${VM_NAME}.qcow2,size=${DISK_SIZE_GB},bus=scsi,cache=unsafe" \
    --network default \
    --graphics none \
    --location "${iso_path}${location}" \
    --initrd-inject="${WORKSPACE}/${VM_NAME}/${KS_FILE}" \
    --extra-args="$(eval echo "${BOOT_COMMAND[@]}")" \
    --transient \
    "${virt_install_args[@]}"
}

#######################################
# Customize Oracle Linux: run provisionning scripts
# Uses libguestfs to update the ${WORKSPACE}/${VM_NAME}/${VM_NAME}.qcow2
# Globals:
#   BUILD_INFO, MEM_SIZE, PROVISION_DIR, PROVISION_SCRIPT, SELINUX, VM_NAME, WORKSPACE
# Arguments:
#   None
# Returns:
#   None
#######################################
image_provision() {
  common::echo_header "Run provisioning scripts"

  local virt_customize_args=()
  if [[ ${SELINUX,,} != disabled ]]; then
    virt_customize_args+=(--selinux-relabel)
  fi

  # Cloud / Custom specific parameters
  if [[ "$(type -t cloud::customize_args)" = 'function' ]]; then
    cloud::customize_args virt_customize_args
  fi
  if [[ "$(type -t cloud_distr::customize_args)" = 'function' ]]; then
    cloud_distr::customize_args virt_customize_args
  fi
  if [[ "$(type -t custom::customize_args)" = 'function' ]]; then
    custom::customize_args virt_customize_args
  fi

  # `run` will run a /bin/sh, therefore we use `run-command`
  virt-customize --copy-in "${WORKSPACE}/${VM_NAME}/${PROVISION_DIR}":/tmp/ \
    --run-command "/bin/bash /tmp/${PROVISION_DIR}/${PROVISION_SCRIPT}" \
    -a "${WORKSPACE}/${VM_NAME}/${VM_NAME}.qcow2" \
    --memsize "${MEM_SIZE}" \
    "${virt_customize_args[@]}"

  virt-copy-out /tmp/builder.log "${WORKSPACE}/${VM_NAME}/" \
    -a "${WORKSPACE}/${VM_NAME}/${VM_NAME}.qcow2"

  virt-copy-out "${BUILD_INFO}" "${WORKSPACE}/${VM_NAME}/" \
    -a "${WORKSPACE}/${VM_NAME}/${VM_NAME}.qcow2"

  local build_info_dir
  build_info_dir=$(basename "${BUILD_INFO}")
  mv "${WORKSPACE}/${VM_NAME}/${build_info_dir}"/* "${WORKSPACE}/${VM_NAME}/"
  rmdir "${WORKSPACE}/${VM_NAME}/${build_info_dir}"
}

#######################################
# Cleanup the image
# Run sysprep / sparsify the ${WORKSPACE}/${VM_NAME}/${VM_NAME}.qcow2 image
# Globals:
#   BUILD_INFO, ROOT_PASSWORD, ROOT_SSH_KEY, SELINUX, VM_NAME, WORKSPACE
# Arguments:
#   None
# Returns:
#   None
#######################################
image_cleanup() {
  common::echo_header "Cleanup"

  local virt_sysprep_args=()
  if [[ ${SELINUX,,} != disabled ]]; then
    virt_sysprep_args+=(--selinux-relabel)
  fi

  # Root access
  virt_sysprep_args+=(--root-password "${ROOT_PASSWORD}" )
  if [[ -n ${ROOT_SSH_KEY} ]]; then
    virt_sysprep_args+=(--ssh-inject "root:${ROOT_SSH_KEY}" )
  fi

  # Cloud / Custom specific parameters
  if [[ "$(type -t cloud::sysprep_args)" = 'function' ]]; then
    cloud::sysprep_args virt_sysprep_args
  fi
  if [[ "$(type -t cloud_distr::sysprep_args)" = 'function' ]]; then
    cloud_distr::sysprep_args virt_sysprep_args
  fi
  if [[ "$(type -t custom::sysprep_args)" = 'function' ]]; then
    custom::sysprep_args virt_sysprep_args
  fi

  virt-sysprep --delete "${BUILD_INFO}" \
    --truncate /etc/machine-id \
    -a "${WORKSPACE}/${VM_NAME}/${VM_NAME}.qcow2" \
    "${virt_sysprep_args[@]}"

  if [[ ${SELINUX,,} != disabled ]]; then
    common::echo_message "SELinux relabel non-root filesystems"
    eval "$(guestfish -a "${WORKSPACE}/${VM_NAME}/${VM_NAME}.qcow2" -i --selinux --listen)"
    local -a mounts
    mapfile -t mounts < <(guestfish --remote mountpoints | awk '{print $2}')
    local mount
    for mount in "${mounts[@]}"; do
      if [[ ${mount} =~ ^(/|(/boot/efi))$ ]]; then
        common::echo_message "    skipping    ${mount}"
      else
        common::echo_message "    relabelling ${mount}"
        guestfish --remote \
          selinux-relabel /etc/selinux/targeted/contexts/files/file_contexts \
          "${mount}"
      fi
    done
    guestfish --remote quit
  fi

  common::echo_message "Sparsify image"
  local tmpdir
  tmpdir=$(mktemp -d -p "${WORKSPACE}/${VM_NAME}")
  virt-sparsify --compress --tmp "${tmpdir}" \
    "${WORKSPACE}/${VM_NAME}/${VM_NAME}.qcow2" \
    "${WORKSPACE}/${VM_NAME}/${VM_NAME}-sparse.qcow2"
  rm -r "${tmpdir}"
  mv "${WORKSPACE}/${VM_NAME}/${VM_NAME}-sparse.qcow2" "${WORKSPACE}/${VM_NAME}/${VM_NAME}.qcow2"

  common::echo_message "Package image"
  if [[ "$(type -t custom::image_package)" = 'function' ]]; then
    custom::image_package
  elif [[ "$(type -t cloud_distr::image_package)" = 'function' ]]; then
    cloud_distr::image_package
  elif [[ "$(type -t cloud::image_package)" = 'function' ]]; then
    cloud::image_package
  else
    common::error "No packaging script found"
  fi
}

#######################################
# Cleanup workspace -- we do not remove the ISO cache!
# Globals:
#   GLOBAL_ENV_FILE, PROVISION_DIR, VM_NAME, WORKSPACE
# Arguments:
#   None
# Returns:
#   None
#######################################
workspace_cleanup() {
  common::echo_header "Cleanup Workspace"

  mv "${GLOBAL_ENV_FILE}" "${WORKSPACE}/${VM_NAME}"
  rm -rf "${WORKSPACE:?}/${VM_NAME}/${PROVISION_DIR}"
}

#######################################
# Main
#######################################
main () {
  source "${BIN_DIR}/common.sh"
  parse_args "$@"
  load_env
  common::retrieve_iso "${ISO_URL}" "${ISO_CHECKSUM}" ISO_PATH
  mkdir "${WORKSPACE}/${VM_NAME}"
  stage_files
  stage_kickstart
  image_create
  image_provision
  image_cleanup
  workspace_cleanup
  common::echo_header "All done"
  common::echo_header "Image available in ${WORKSPACE}/${VM_NAME}"
}

main "$@"
