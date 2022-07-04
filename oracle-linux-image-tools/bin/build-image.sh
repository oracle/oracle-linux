#!/usr/bin/env bash
# shellcheck disable=SC1090
#
# Create minimal Oracle Linux images
#
# Copyright (c) 2019, 2022 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# Description: creates minimal Oracle Linux images which can be used in cloud
# environment.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

# Constants
readonly PGM=$(basename "$0")
readonly BIN_DIR=$( cd "$(dirname "$0")" ; pwd -P )
readonly REPO_DIR=$(dirname "${BIN_DIR}")
readonly DISTR_DIR="${REPO_DIR}/distr"
readonly CLOUD_DIR="${REPO_DIR}/cloud"
readonly CUSTOM_DIR="${REPO_DIR}/custom"
readonly TEMPLATE_DIR="${REPO_DIR}/packer-template"
readonly ENV_FILE="env.properties"
readonly ENV_FILE_DEFAULTS="${REPO_DIR}/${ENV_FILE}.defaults"
readonly FILES_DIR="files"
readonly PACKER_FILES="packer_files"
readonly SHUTDOWN_CMD="shutdown -P now; init 0"
readonly PROVISION_SCRIPT="provision.sh"
readonly IMAGE_SCRIPTS="image-scripts.sh"
readonly MOUNT_IMAGE="${BIN_DIR}/mnt-img.sh"

# Exit on error
set -e

#######################################
# Print usage message and exit
# Globals:
#   PGM REPO_DIR ENV_FILE
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
# Print header
# Globals:
#   PGM
# Arguments:
#   None
# Returns:
#   None
#######################################
echo_header() {
  echo "$(tput setaf 2)+++ ${PGM}: $*$(tput sgr 0)"
}

#######################################
# Print message
# Globals:
#   PGM
# Arguments:
#   None
# Returns:
#   None
#######################################
echo_message() {
  echo "    ${PGM}: $*"
}

#######################################
# Print error message and exit
# Globals:
#   PGM
# Arguments:
#   message
# Returns:
#   None
#######################################
error() {
  echo "$(tput setaf 1)+++ ${PGM}: $*$(tput sgr 0)" >&2
  exit 1
}

#######################################
# Parse arguments
# Exit on error.
# Globals:
#   ENV_FILE LOCAL_ENV_FILE REPO_DIR
# Arguments:
#   Command line
# Returns:
#   None
#######################################
parse_args() {
  echo_header "Parse arguments"

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
#   LOCAL_ENV_FILE GLOBAL_ENV_FILE DISTR CLOUD WORKSPACE PACKER_FILES
#   Loaded environment files...
# Arguments:
#   None
# Returns:
#   None
#######################################
load_env() {
  echo_header "Load environment"

  local file

  [[ -e "${ENV_FILE_DEFAULTS}" ]] ||
    error "missing default env file '${ENV_FILE_DEFAULTS}'"
  source "${ENV_FILE_DEFAULTS}"

  [[ -e "${LOCAL_ENV_FILE}" ]] ||
    error "env file '${LOCAL_ENV_FILE}' does not exists"
  source "${LOCAL_ENV_FILE}"

  # Check for minimal environment
  [[ -z "${WORKSPACE}" ]] && error "no workspace directory defined"
  [[ -d "${WORKSPACE}" ]] ||
    error "workspace directory '${WORKSPACE}' does not exist"
  [[ -z "${DISTR}" ]] && error "no distribution defined"
  [[ -d "${DISTR_DIR}/${DISTR}" ]] || error "no such distribution: ${DISTR}"
  [[ -z "${CLOUD}" ]] && error "no cloud defined"
  [[ -d "${CLOUD_DIR}/${CLOUD}" ]] || error "no such cloud: ${CLOUD}"
  [[ -z "${CUSTOM}" ]] && 
    error "no custom project defined (use 'none' for no customization)"
  [[ "${CUSTOM}" == "none" || -d "${CUSTOM_DIR}/${CUSTOM}" ]] || 
    error "no such custom project: ${CUSTOM}"

  # Generate global env file
  rm -rf "${WORKSPACE:?}/${PACKER_FILES}"
  mkdir "${WORKSPACE}/${PACKER_FILES}"
  readonly GLOBAL_ENV_FILE="${WORKSPACE}/${PACKER_FILES}/${ENV_FILE}"
  for file in \
    "${ENV_FILE_DEFAULTS}" \
    "${DISTR_DIR}/${DISTR}/${ENV_FILE}" \
    "${CLOUD_DIR}/${CLOUD}/${ENV_FILE}" \
    "${CLOUD_DIR}/${CLOUD}/${DISTR}/${ENV_FILE}" \
    "${CUSTOM_DIR}/${CUSTOM}/${ENV_FILE}" \
    "${LOCAL_ENV_FILE}"
  do
    [[ -r "${file}" ]] && cat "${file}" >> "${GLOBAL_ENV_FILE}"
  done

  # Load it
  source "${GLOBAL_ENV_FILE}"

  readonly WORKSPACE DISTR CLOUD CUSTOM

  # Basic validation
  [[ ${PACKER_BUILDER} =~ ^(virtualbox-iso\.|qemu\.) ]] ||
    error "Invalid PACKER_BUILDER: ${PACKER_BUILDER}"
  [[ ${PACKER_BUILDER} =~ ^qemu\. && -n ${QEMU_BINARY} && ! -x ${QEMU_BINARY} ]] &&
    error "QEMU binary ${QEMU_BINARY} not found"

  [[ -z "${ISO_URL}" ]] && error "missing ISO URL"
  [[ -z "${ISO_CHECKSUM}" ]] && error "missing ISO checksum"
  readonly ISO_URL ISO_CHECKSUM

  [[ -z "${SSH_PASSWORD}" && -z "${SSH_KEY_FILE}" ]] &&
    error "need at least ssh key or password"
	if [[ -n "${SSH_KEY_FILE}" ]]; then
    if [[ -r "${SSH_KEY_FILE}.pub" ]]; then
      SSH_PUB_KEY=$(cat "${SSH_KEY_FILE}.pub")
    else
      error "missing public key file: ${SSH_KEY_FILE}.pub"
    fi
  fi
  [[ -n "${SSH_PASSWORD}" || -r "${SSH_KEY_FILE}" ]] ||
    error "missing private key file: ${SSH_KEY_FILE}"
  readonly SSH_PASSWORD SSH_KEY_FILE SSH_PUB_KEY

  [[ "${LOCK_ROOT,,}" =~ ^(yes)|(no)$ ]] || error "LOCK_ROOT must be yes or no"
  readonly LOCK_ROOT

  # Attempt to derive DISTR_NAME from the iso image name, otherwise fall back
  # to the configured name
  local distr_name
  # shellcheck disable=SC2001
  distr_name=$(sed -e 's/^.*OracleLinux-R\([[:digit:]]\)-U\([[:digit:]]\+\)\(-Server\)\?-\([^-]\+\)\(-dvd\)\?\(-[[:digit:]]\+\)\?\.iso$/OL\1U\2_\4/' <<< "${ISO_URL}")
  if [[ $distr_name =~ ^OL[678]U ]]; then
    DISTR_NAME="${distr_name}"
  fi

  [[ -z "${DISTR_NAME}" && -z "${BUILD_NUMBER}" ]] &&
    error "missing distribution name / build number"
  if [[ -z "${VM_NAME}" ]]; then
    VM_NAME="${DISTR_NAME}-${CLOUD}-b${BUILD_NUMBER}"
  fi
  KS_FILE="${VM_NAME}-ks.cfg"
  readonly DISTR_NAME BUILD_NUMBER VM_NAME

  [[ -e "${WORKSPACE}/${VM_NAME}" ]] &&
    error "${WORKSPACE}/${VM_NAME} already exists"

  [[ ${DISK_SIZE_GB} =~ ^[0-9]+$ ]] || error "disk size is not numeric"
  DISK_SIZE_MB=$(( DISK_SIZE_GB * 1024 ))
  readonly DISK_SIZE_GB DISK_SIZE_MB

  [[ "${SETUP_SWAP,,}" =~ ^(yes)|(no)$ ]] || error "SETUP_SWAP must be yes or no"
  readonly SETUP_SWAP

  [[ "${SELINUX,,}" =~ ^(enforcing)|(permissive)|(disabled)$ ]] || error "SELINUX must be enforcing, permissive or disabled"
  readonly SELINUX

  [[ "${X2APIC,,}" =~ ^(on)|(off)$ ]] || error "X2APIC must be on or off"
  readonly X2APIC="${X2APIC,,}"

  [[ "${SERIAL_CONSOLE,,}" =~ ^(yes)|(no)$ ]] || error "SERIAL_CONSOLE must be yes or no"
  readonly SERIAL_CONSOLE

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
# Stage required files for packer
# Globals:
#   DISTR CLOUD WORKSPACE PACKER_FILES
#   Loaded environment files...
# Arguments:
#   None
# Returns:
#   None
#######################################
stage_files() {
  echo_header "Stage Packer files"

  # Cloud files into cloud subdir
  mkdir -p "${WORKSPACE}/${PACKER_FILES}/cloud/distr"
  if [[ -d "${CLOUD_DIR}/${CLOUD}/${FILES_DIR}" ]]; then
    cp -RL "${CLOUD_DIR}/${CLOUD}/${FILES_DIR}/." "${WORKSPACE}/${PACKER_FILES}/cloud"
  fi
  if [[ -d "${CLOUD_DIR}/${CLOUD}/${DISTR}/${FILES_DIR}" ]]; then
    cp -RL "${CLOUD_DIR}/${CLOUD}/${DISTR}/${FILES_DIR}/." "${WORKSPACE}/${PACKER_FILES}/cloud/distr"
  fi
  # Distr files into distr subdir
  mkdir "${WORKSPACE}/${PACKER_FILES}/distr"
  if [[ -d "${DISTR_DIR}/${DISTR}/${FILES_DIR}" ]]; then
    cp -RL "${DISTR_DIR}/${DISTR}/${FILES_DIR}/." "${WORKSPACE}/${PACKER_FILES}/distr"
  fi
  # Custom files into custom subdir
  mkdir "${WORKSPACE}/${PACKER_FILES}/custom"
  if [[ -d "${CUSTOM_DIR}/${CUSTOM}/${FILES_DIR}" ]]; then
    cp -RL "${CUSTOM_DIR}/${CUSTOM}/${FILES_DIR}/." "${WORKSPACE}/${PACKER_FILES}/custom"
  fi

  # Provisioners
  if [[ -r "${CLOUD_DIR}/${CLOUD}/${PROVISION_SCRIPT}" ]]; then
    cp "${CLOUD_DIR}/${CLOUD}/${PROVISION_SCRIPT}" "${WORKSPACE}/${PACKER_FILES}/cloud/"
  fi
  if [[ -r "${CLOUD_DIR}/${CLOUD}/${DISTR}/${PROVISION_SCRIPT}" ]]; then
    cp "${CLOUD_DIR}/${CLOUD}/${DISTR}/${PROVISION_SCRIPT}" "${WORKSPACE}/${PACKER_FILES}/cloud/distr/"
  fi
  if [[ -r "${DISTR_DIR}/${DISTR}/${PROVISION_SCRIPT}" ]]; then
    cp "${DISTR_DIR}/${DISTR}/${PROVISION_SCRIPT}" "${WORKSPACE}/${PACKER_FILES}/distr/"
  fi
  if [[ -r "${CUSTOM_DIR}/${CUSTOM}/${PROVISION_SCRIPT}" ]]; then
    cp "${CUSTOM_DIR}/${CUSTOM}/${PROVISION_SCRIPT}" "${WORKSPACE}/${PACKER_FILES}/custom"
  fi
}

#######################################
# Stage kickstart file
# Globals:
#   BIN_DIR
#   DISTR_DIR DISTR
#   KS_FILE
#   SETUP_SWAP
#   SSH_PASSWORD SSH_PUB_KEY
#   WORKSPACE
# Arguments:
#   None
# Returns:
#   None
#######################################
stage_kickstart() {
  echo_header "Stage kickstart file"

  local hash

  cp "${DISTR_DIR}/${DISTR}/"*-ks.cfg "${WORKSPACE}/${KS_FILE}"

  if [[ -z "${SSH_PASSWORD}" ]]; then
    sed -i -e 's/^rootpw .*$/rootpw --lock/' "${WORKSPACE}/${KS_FILE}"
  else
    # hash=$("${BIN_DIR}/mkpasswd-osx.py" "${SSH_PASSWORD}")
    hash=$("${BIN_DIR}/mkpasswd.py" "${SSH_PASSWORD}")
    # '/' is a valid character in a SHA512 hash salt!
    sed -i -e 's!^rootpw .*$!rootpw --iscrypted '"${hash}"'!' \
      "${WORKSPACE}/${KS_FILE}"
  fi

  if [[ -n "${SSH_PUB_KEY}" ]]; then
    sed -i -e \
      $'s!^rootpw .*$!&\\\nsshkey --username root "'"${SSH_PUB_KEY}"'"!' \
      "${WORKSPACE}/${KS_FILE}"
  fi

  if [[ "${SETUP_SWAP,,}" = "no" ]]; then
    sed -i -e '/^part swap /d' "${WORKSPACE}/${KS_FILE}"
  fi

  if [[ -n "${REPO_URL}" ]]; then
    sed -i -e \
      '/^# URL to an installation tree/a url --url "'"${REPO_URL}"'"' \
      "${WORKSPACE}/${KS_FILE}"
  fi

  local ks_repo
  for ks_repo in "${!REPO[@]}"; do
    sed -i -e \
      '/^# Additional yum repositories/a repo --name "'"${ks_repo}"'" --baseurl "'"${REPO[${ks_repo}]}"'"' \
      "${WORKSPACE}/${KS_FILE}"
  done

  # Kickstart fixups at distr / cloud_distr level
  if [[ "$(type -t distr::kickstart)" = 'function' ]]; then
    distr::kickstart "${WORKSPACE}/${KS_FILE}"
  fi
  if [[ "$(type -t cloud_distr::kickstart)" = 'function' ]]; then
    cloud_distr::kickstart "${WORKSPACE}/${KS_FILE}"
  fi
  if [[ "$(type -t custom::kickstart)" = 'function' ]]; then
    custom::kickstart "${WORKSPACE}/${KS_FILE}"
  fi
}

#######################################
# Generate Packer config file
# Globals:
#   DISK_SIZE_MB MEM_SIZE CPU_NUM
#   ISO_URL ISO_CHECKSUM
#   KS_FILE
#   QEMU_BINARY
#   SERIAL_CONSOLE
#   SHUTDOWN_CMD
#   SSH_PASSWORD SSH_KEY_FILE
#   VM_NAME
#   WORKSPACE PACKER_FILES BIN_DIR PROVISION_SCRIPT
#   X2APIC
# Arguments:
#   None
# Returns:
#   None
#######################################
packer_conf() {
  echo_header "Generate Packer configuration file"

  local q='"'
  # KS_CONFIG is expanded in BOOT_COMMAND
  # shellcheck disable=SC2034
  local KS_CONFIG="http://{{ .HTTPIP }}:{{ .HTTPPort }}/${KS_FILE}"
  # shellcheck disable=SC2034
  local CONSOLE=""
  local modifyvm_console=""
  local qemu_serial_console=""
  if [[ "${SERIAL_CONSOLE,,}" = "yes" ]]; then
    # shellcheck disable=SC2034
    CONSOLE=" console=tty0 console=ttyS0"
    modifyvm_console='["modifyvm", "{{.Name}}", "--uart1", "0x3f8", 4, "--uartmode1", "file", "'"${WORKSPACE}/${VM_NAME}"'/serial-console.txt"],'
    qemu_serial_console='[ "-serial", "file:'"${WORKSPACE}/${VM_NAME}"'/serial-console.txt" ]'
  fi

  cat > "${WORKSPACE}/${VM_NAME}.pkrvars.hcl" <<-EOF
		# Variables file for ${VM_NAME}
		workspace             = "${WORKSPACE}"
		iso_url               = "${ISO_URL}"
		iso_checksum          = "${ISO_CHECKSUM}"
		vm_name               = "${VM_NAME}"
		disk_size             = ${DISK_SIZE_MB}
		memory                = ${MEM_SIZE}
		cpus                  = ${CPU_NUM}
		${SSH_PASSWORD:+ssh_password          = ${q}$SSH_PASSWORD${q}}
		${SSH_KEY_FILE:+ssh_private_key_file  = ${q}$SSH_KEY_FILE${q}}
		boot_command          = [
		$(eval echo -e "\"$(printf '  \\"%s\\",\\n' "${BOOT_COMMAND[@]}")\"")
		]
		shutdown_command      = "${SHUTDOWN_CMD}"
		vbox_manage           = [ ${modifyvm_console} ]
		x2apic                = "${X2APIC}"
		${QEMU_BINARY:+qemu_binary           = ${q}$QEMU_BINARY${q}}
		qemu_args             = [ ${qemu_serial_console} ]
		packer_files          = "${WORKSPACE}/${PACKER_FILES}"
		provision_script      = "${BIN_DIR}/${PROVISION_SCRIPT}"
	EOF

  # Packer config specific to distr / cloud / cloud_distr level
  if [[ "$(type -t distr::packer_conf)" = 'function' ]]; then
    distr::packer_conf "${WORKSPACE}/${VM_NAME}.pkrvars.hcl"
  fi
  if [[ "$(type -t cloud::packer_conf)" = 'function' ]]; then
    cloud::packer_conf "${WORKSPACE}/${VM_NAME}.pkrvars.hcl"
  fi
  if [[ "$(type -t cloud_distr::packer_conf)" = 'function' ]]; then
    cloud_distr::packer_conf "${WORKSPACE}/${VM_NAME}.pkrvars.hcl"
  fi
  if [[ "$(type -t custom::packer_conf)" = 'function' ]]; then
    custom::packer_conf "${WORKSPACE}/${VM_NAME}.pkrvars.hcl"
  fi
}

#######################################
# Run packer
# Globals:
#   PACKER_BUILDER
#   SERIAL_CONSOLE
#   VM_NAME
#   WORKSPACE
# Arguments:
#   None
# Returns:
#   None
#######################################
run_packer() {
  echo_header "Run Packer"

  cd "${WORKSPACE}"
  local packer_status serial_pid

  if [[ ${SERIAL_CONSOLE,,} == "yes" ]]; then
    # Print serial console output ([try to] suppress escape sequences)
    echo_message "Monitoring serial console"
    # shellcheck disable=SC2155
    local monitor="$(shopt -po monitor)"
    set -m
    (
      while [[ ! -f "${WORKSPACE}/${VM_NAME}/serial-console.txt" ]]; do
        sleep 10
      done
      sleep 10
      echo "$(tput setaf 4)--- serial console: Showing serial console output$(tput sgr 0)"
      tail -f "${WORKSPACE}/${VM_NAME}/serial-console.txt" |
        sed  -e "s,\x1B\[[0-9;]*[a-zA-Z],,g" \
             -e "s/\x0D//g" \
             -e '/^$/d' \
             -e "s/^/$(tput setaf 4)    serial console: /" \
             -e "s/\$/$(tput sgr 0)/"
    )&
    serial_pid=$!
    eval "${monitor}"
  fi

  # shellcheck disable=SC2155
  local errexit="$(shopt -po errexit)"
  set +e
  # shellcheck disable=SC2086
  "${PACKER}" build -only "${PACKER_BUILDER}" ${PACKER_BUILD_OPTIONS} \
    -var-file="${VM_NAME}.pkrvars.hcl" \
    "${TEMPLATE_DIR}"
  packer_status=$?
  eval "${errexit}"

  if [[ -n "${serial_pid}" ]]; then
    echo_message "Stop monitoring serial console"
    kill -- -${serial_pid}
  fi

  [[ ${packer_status} -ne 0 ]] && error "Packer didn't complete successfully"

  [[ -r "${WORKSPACE}/${VM_NAME}/${VM_NAME}.ova" || -r "${WORKSPACE}/${VM_NAME}/System.img" ]] ||
    error "Packer didn't built the image"
}

#######################################
# Cleanup actions run directly on the image
# We prune work images as soon as possible to limit disk space usage
# Globals:
#   PACKER_BUILDER
#   WORKSPACE VM_NAME
#   MOUNT_IMAGE
#   Loaded environment files used in invoked modules
# Arguments:
#   None
# Returns:
#   None
#######################################
image_cleanup() {
  echo_header "Cleanup image"

  local boot_fs root_fs
  local mnt="${WORKSPACE}/${VM_NAME}/mnt"

  echo_message "Extract image and convert to raw format"
  cd "${WORKSPACE}/${VM_NAME}"
  if common::is_vbox ; then
    tar -xf "${VM_NAME}.ova"
    mv "${VM_NAME}.ova" System.ova
    mv -f "${VM_NAME}"-disk*.vmdk System.vmdk
    vbox-img convert \
      --srcfilename System.vmdk \
      --dstfilename System.img \
      --srcformat VMDK \
      --dstformat RAW
    rm -f System.vmdk
  fi

  # Run cleanup scripts
  if [[ "$(type -t custom::image_cleanup)" = 'function' ||
    "$(type -t cloud_distr::image_cleanup)" = 'function' ||
    "$(type -t cloud::image_cleanup)" = 'function' ||
    "$(type -t distr::image_cleanup)" = 'function' ]]; then
    # Only mount the image if we have an image_cleanup function defined
    echo_message "Loopback mount image"
    # Loopback mount the image
    # We will have the following subdirectories:
    #   - 1: /boot
    #   - 2: root filesystem (/)
    #        In case of a btrfs filesystem, / will be in root subvolume
    # Should /boot be part of the btrfs volume we then have:
    #   - 1: btrfs volume with boot and root subvolumes
    rm -rf "${mnt}"
    mkdir "${mnt}"
    sudo "${MOUNT_IMAGE}" System.img "${mnt}"
    if [[ $(stat -f -c "%T" "${mnt}/1") = "btrfs" ]]; then
      # Both / and /boot are on BTRFS
      boot_fs="${mnt}/1/boot"
      root_fs="${mnt}/1/root"
    else
      boot_fs="${mnt}/1"
      if [[ $(stat -f -c "%T" "${mnt}/2") = "btrfs" ]]; then
        root_fs="${mnt}/2/root"
      else
        root_fs="${mnt}/2"
      fi
    fi

    # Basic check to see if we have the "right" partitions mounted
    if [[ ! -d "${root_fs}/etc" || ! -d "${boot_fs}/grub2" ]]; then
      sudo "${MOUNT_IMAGE}" -u System.img
      rm -rf "${mnt}"
      error "Loopback mount failed"
    fi

    # Run cleanup scripts
    if [[ "$(type -t custom::image_cleanup)" = 'function' ]]; then
      echo_message "Run custom cleanup"
      custom::image_cleanup "${root_fs}" "${boot_fs}"
    fi
    if [[ "$(type -t cloud_distr::image_cleanup)" = 'function' ]]; then
      echo_message "Run cloud distribution cleanup"
      cloud_distr::image_cleanup "${root_fs}" "${boot_fs}"
    fi
    if [[ "$(type -t cloud::image_cleanup)" = 'function' ]]; then
      echo_message "Run cloud cleanup"
      cloud::image_cleanup "${root_fs}" "${boot_fs}"
    fi
    if [[ "$(type -t distr::image_cleanup)" = 'function' ]]; then
      echo_message "Run distribution cleanup"
      distr::image_cleanup "${root_fs}" "${boot_fs}"
    fi

    # Ensure we are still in the image directory
    cd "${WORKSPACE}/${VM_NAME}"
    # unmount and trim image
    echo_message "Unmount and trim image"
    sudo -- bash -c '
      sync; sync; sync;
      fstrim "'"${boot_fs}"'";
      fstrim "'"${root_fs}"'";
      '
    sudo "${MOUNT_IMAGE}" -u System.img
    rm -rf "${mnt}"

    cp --sparse=always System.img System.img.sparse
    mv -f System.img.sparse System.img
  fi

  echo_message "Package image"
  if [[ "$(type -t custom::image_package)" = 'function' ]]; then
    custom::image_package
  elif [[ "$(type -t cloud_distr::image_package)" = 'function' ]]; then
    cloud_distr::image_package
  elif [[ "$(type -t cloud::image_package)" = 'function' ]]; then
    cloud::image_package
  else
    error "No packaging script found"
  fi

  if common::is_vbox ; then
    rm "${WORKSPACE}/${VM_NAME}/${VM_NAME}.ovf"
    rm "${WORKSPACE}/${VM_NAME}/System.ova"
  fi
}

#######################################
# Cleanup workspace -- we do not remove the packer cache!
# Globals:
#   WORKSPACE VM_NAME
#   GLOBAL_ENV_FILE
#   KS_FILE
#   PACKER_FILES
# Arguments:
#   None
# Returns:
#   None
#######################################
cleanup() {
  echo_header "Cleanup Workspace"

  mv "${WORKSPACE}/${KS_FILE}" "${WORKSPACE}/${VM_NAME}"
  mv "${WORKSPACE}/${VM_NAME}.pkrvars.hcl" "${WORKSPACE}/${VM_NAME}"
  mv "${GLOBAL_ENV_FILE}" "${WORKSPACE}/${VM_NAME}"
  rm -rf "${WORKSPACE:?}/${PACKER_FILES}"
}

#######################################
# Main
#######################################
main () {
  parse_args "$@"
  source "${BIN_DIR}/common.sh"
  load_env
  stage_files
  stage_kickstart
  packer_conf
  run_packer
  image_cleanup
  cleanup
  echo_header "All done"
  echo_header "Image available in ${WORKSPACE}/${VM_NAME}"
}

main "$@"
