#!/usr/bin/env bash
#
# Create minimal Oracle Linux images
#
# Copyright (c) 2019,2020 Oracle and/or its affiliates.
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
  echo "$(tput setaf 2)+++ ${PGM}: $@$(tput sgr 0)"
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
  echo "    ${PGM}: $@"
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
  echo "$(tput setaf 1)+++ ${PGM}: $@$(tput sgr 0)" >&2
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

  # Generate global env file
  rm -rf "${WORKSPACE}/${PACKER_FILES}"
  mkdir "${WORKSPACE}/${PACKER_FILES}"
  readonly GLOBAL_ENV_FILE="${WORKSPACE}/${PACKER_FILES}/${ENV_FILE}"
  for file in \
    "${ENV_FILE_DEFAULTS}" \
    "${DISTR_DIR}/${DISTR}/${ENV_FILE}" \
    "${CLOUD_DIR}/${CLOUD}/${ENV_FILE}" \
    "${LOCAL_ENV_FILE}"
  do
    [[ -r "${file}" ]] && cat "${file}" >> "${GLOBAL_ENV_FILE}"
  done

  # Load it
  source "${GLOBAL_ENV_FILE}"

  readonly WORKSPACE DISTR CLOUD

  # Basic validation
  [[ -z "${ISO_URL}" ]] && error "missing ISO URL"
  [[ -z "${ISO_SHA1_CHECKSUM}" ]] && error "missing ISO checksum"
  readonly ISO_URL ISO_SHA1_CHECKSUM

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

  [[ -z "${DISTR_NAME}" && -z "${BUILD_NUMBER}" ]] &&
    error "missing distribution name / build number"
  VM_NAME="${DISTR_NAME}-${CLOUD}-b${BUILD_NUMBER}"
  KS_FILE="${VM_NAME}-ks.cfg"
  readonly DISTR_NAME BUILD_NUMBER VM_NAME

  [[ -e "${WORKSPACE}/${VM_NAME}" ]] &&
    error "${WORKSPACE}/${VM_NAME} already exists"

  [[ ${DISK_SIZE_GB} =~ ^[0-9]+$ ]] || error "disk size is not numeric"
  DISK_SIZE_MB=$(( ${DISK_SIZE_GB} * 1024 ))
  readonly DISK_SIZE_GB DISK_SIZE_MB

  [[ "${SETUP_SWAP,,}" =~ ^(yes)|(no)$ ]] || error "SETUP_SWAP must be yes or no"
  readonly SETUP_SWAP

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
      's!^rootpw .*$!&\'$'\n'"sshkey --username root \"${SSH_PUB_KEY}\"!" \
      "${WORKSPACE}/${KS_FILE}"
  fi

  if [[ "${SETUP_SWAP,,}" = "no" ]]; then
    sed -i -e '/^part swap /d' "${WORKSPACE}/${KS_FILE}"
  fi

  # Kickstart fixups at distr / cloud_distr level
  if [[ "$(type -t distr::kickstart)" = 'function' ]]; then
    distr::kickstart "${WORKSPACE}/${KS_FILE}"
  fi
  if [[ "$(type -t cloud_distr::kickstart)" = 'function' ]]; then
    cloud_distr::kickstart "${WORKSPACE}/${KS_FILE}"
  fi
}

#######################################
# Generate Packer config file
# Globals:
#   DISK_SIZE_MB MEM_SIZE CPU_NUM
#   ISO_URL ISO_SHA1_CHECKSUM
#   KS_FILE
#   SHUTDOWN_CMD
#   SSH_PASSWORD SSH_KEY_FILE
#   VM_NAME
#   WORKSPACE PACKER_FILES BIN_DIR PROVISION_SCRIPT
# Arguments:
#   None
# Returns:
#   None
#######################################
packer_conf() {
  echo_header "Generate Packer configuration file"

  local q='"'
  # KS_CONFIG is expanded in BOOT_COMMAND
  local KS_CONFIG="http://{{ .HTTPIP }}:{{ .HTTPPort }}/${KS_FILE}"
  local boot_command=$(eval echo "\"${BOOT_COMMAND}\"")

  cat > "${WORKSPACE}/${VM_NAME}.json" <<-EOF
	{
	  "builders":
	  [
	    {
	      "type": "virtualbox-iso",
	      "guest_os_type": "Oracle_64",
	      "iso_url": "${ISO_URL}",
	      "iso_checksum_type": "sha1",
	      "iso_checksum": "${ISO_SHA1_CHECKSUM}",
	      "output_directory": "${WORKSPACE}/${VM_NAME}",
	      "vm_name": "${VM_NAME}",
	      "hard_drive_interface": "sata",
	      "disk_size": "${DISK_SIZE_MB}",
	      "guest_additions_mode": "attach",
	      "format": "ova",
	      "headless": "true",
	      "ssh_username": "root",
	      ${SSH_PASSWORD:+${q}ssh_password${q}: ${q}$SSH_PASSWORD${q},}
	      ${SSH_KEY_FILE:+${q}ssh_private_key_file${q}: ${q}$SSH_KEY_FILE${q},}
	      "ssh_port": 22,
	      "ssh_wait_timeout": "30m",
        "http_directory": "${WORKSPACE}",
	      "boot_wait": "20s",
	      "boot_command":
	      [
	        "${boot_command}"
	      ],
	      "shutdown_command": "$SHUTDOWN_CMD",
	      "vboxmanage":
	      [
	        ["modifyvm", "{{.Name}}", "--memory", ${MEM_SIZE}],
	        ["modifyvm", "{{.Name}}", "--cpus", ${CPU_NUM}]
	      ]
	    }
	  ],
	  "provisioners":
	  [
	    {
	      "type": "file",
	      "source": "${WORKSPACE}/${PACKER_FILES}",
	      "destination": "/tmp"
	    },
	    {
	      "type": "shell",
	      "script": "${BIN_DIR}/${PROVISION_SCRIPT}"
	    }
	  ]
	}
	EOF
}

#######################################
# Run packer
# Globals:
#   VM_NAME
#   WORKSPACE
# Arguments:
#   None
# Returns:
#   None
#######################################
run_packer() {
  echo_header "Run Packer"

  cd ${WORKSPACE}
  local packer_status
  local errexit="$(shopt -po errexit)"
  set +e
  /usr/bin/packer build -on-error=ask ${VM_NAME}.json
  packer_status=$?
  eval "${errexit}"

  [[ ${packer_status} -ne 0 ]] && error "Packer didn't complete successfully"

  [[ -r "${WORKSPACE}/${VM_NAME}/${VM_NAME}.ova" ]] ||
    error "Packer didn't built the image"
}

#######################################
# Cleanup actions run directly on the image
# We prune work images as soon as possible to limit disk space usage
# Globals:
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
  tar -xf "${VM_NAME}.ova"
  rm "${VM_NAME}.ova"
  mv -f "${VM_NAME}"-disk*.vmdk System.vmdk
  vbox-img convert \
    --srcfilename System.vmdk \
    --dstfilename System.img \
    --srcformat VMDK \
    --dstformat RAW
  rm -f System.vmdk

  echo_message "Loopback mount image"
  # Loopback mount the image
  # We will have the following subdirectories:
  #   - 1: /boot
  #   - 2: root filesystem (/)
  #        In case of a btrfs filesystem, / will be in root subvolume
  rm -rf "${mnt}"
  mkdir "${mnt}"
  sudo ${MOUNT_IMAGE} System.img "${mnt}"
  boot_fs="${mnt}/1"
  if df -T "${mnt}/2" | grep -q btrfs; then
    root_fs="${mnt}/2/root"
  else
    root_fs="${mnt}/2"
  fi

  # Run cleanup scripts
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
  sudo -- bash -c '\
    sync; sync; sync; \
    fstrim "'${boot_fs}'"; \
    fstrim "'${root_fs}'"; \
    '
  sudo ${MOUNT_IMAGE} -u System.img
  cp --sparse=always System.img System.img.sparse
  mv -f System.img.sparse System.img
  rm -rf "${mnt}"

  echo_message "Package image"
  if [[ "$(type -t cloud_distr::image_package)" = 'function' ]]; then
    cloud_distr::image_package
  elif [[ "$(type -t cloud::image_package)" = 'function' ]]; then
    cloud::image_package
  else
    error "No packaging script found"
  fi

  rm "${WORKSPACE}/${VM_NAME}/${VM_NAME}.ovf"
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
  mv "${WORKSPACE}/${VM_NAME}.json" "${WORKSPACE}/${VM_NAME}"
  mv "${GLOBAL_ENV_FILE}" "${WORKSPACE}/${VM_NAME}"
  rm -rf "${WORKSPACE}/${PACKER_FILES}"
}

#######################################
# Main
#######################################
main () {
  parse_args "$@"
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
