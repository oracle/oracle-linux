#!/usr/bin/env bash
#
# Common function for the image builder script
#
# Copyright (c) 2022, 2024 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

#######################################
# Print header
# Globals:
#   PGM
# Arguments:
#   None
# Returns:
#   None
#######################################
common::echo_header() {
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
common::echo_message() {
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
common::error() {
  echo "$(tput setaf 1)+++ ${PGM}: $*$(tput sgr 0)" >&2
  exit 1
}

#######################################
# Generate manifest
# Globals:
#   None
# Arguments:
#   - files to include in the manifest
# Returns:
#   - writes manifest to stdout
#######################################
common::make_manifest() {
  sha1sum "$@" | sed --regexp-extended 's/(.*) +(.*)/SHA1(\2)= \1/g'
}

#######################################
# Make ova from the specified files
# Globals:
#   VM_NAME
# Arguments:
#   files to include in ova
# Returns:
#   - $VM_NAME.ova file generated
#   - included files removed
#######################################
common::make_ova() {
  tar -cvf "${VM_NAME}.ova" --remove-files "$@"
}

#######################################
# Convert disk image to QEMU 'qcow2' format
# Globals:
#   None
# Arguments:
#   1: output file name (including .qcow2 extension)
#   -: implicit use of `System.img`
# Returns:
#   - $output file generated
#   - System.img file removed
#######################################
common::convert_to_qcow2() {
  local output=${1:?- ***error*** \'output\' not set}
  qemu-img convert -c -f raw -O qcow2 System.img "${output}"
  rm System.img
}

#######################################
# Convert disk image (QCOW2) to VMDK format
# Globals:
#   VM_NAME, WORKSPACE
# Arguments:
#   1: output file name (including .vmdk extension)
#   -: implicit use of `${WORKSPACE}/${VM_NAME}/${VM_NAME}.qcow2`
# Returns:
#   - $output file generated
#   - ${VM_NAME}.qcow2 file removed
#######################################
common::convert_to_vmdk() {
  local output=${1:?- ***error*** \'output\' not set}
  local input="${WORKSPACE}/${VM_NAME}/${VM_NAME}.qcow2"
  qemu-img convert -f qcow2 -O vmdk -o subformat=streamOptimized "${input}" "${output}"
  rm "${input}"
}


#######################################
# Fix VMDK header
# In VirtualBox, grub2 is extremely slow if BIOS geometries are not defined
# in the VMDK header.
# We also add UUIDs for the sake of completeness.
# Globals:
#   None
# Arguments:
#   1: vmdk file to patch
#   2: file uuid
# Returns:
#   vmdk file patched in-place
#######################################
common::fix_vmdk_header() {
  local vmdk=${1:?- ***error*** \'vmdk\' not set}
  local uuid=${2:?- ***error*** \'uuid\' not set}
  local cylinders heads sectors
  local disk_descriptor_file patch_file

  disk_descriptor_file=$(mktemp -t ddb-XXXXXXXX.txt)
  patch_file=$(mktemp -t patch-XXXXXXXX.txt)

  dd if="${vmdk}" of="${disk_descriptor_file}" bs=1 skip=512 count=1024

  cylinders=$(grep -a ddb.geometry.cylinders "${disk_descriptor_file}" | sed -e 's/.* = //')
  heads=$(grep -a ddb.geometry.heads "${disk_descriptor_file}" | sed -e 's/.* = //')
  sectors=$(grep -a ddb.geometry.sectors "${disk_descriptor_file}" | sed -e 's/.* = //')
  cat >"${patch_file}" <<-EOF
		ddb.geometry.biosCylinders=${cylinders}
		ddb.geometry.biosHeads=${heads}
		ddb.geometry.biosSectors=${sectors}
		ddb.uuid.image="${uuid}"
		ddb.uuid.parent="00000000-0000-0000-0000-000000000000"
		ddb.uuid.modification="00000000-0000-0000-0000-000000000000"
		ddb.uuid.parentmodification="00000000-0000-0000-0000-000000000000"
		EOF
  sed -i -e "/ddb.geometry.sectors/r ${patch_file}" "${disk_descriptor_file}"

  dd conv=notrunc,nocreat if="${disk_descriptor_file}" of="${vmdk}" bs=1 seek=512 count=1024

  rm "${disk_descriptor_file}" "${patch_file}"
}
#######################################
# Convert disk image to VHD format
# Globals:
#   VM_NAME, WORKSPACE
# Arguments:
#   1: output file name (including .vhd extension)
#   -: implicit use of `${WORKSPACE}/${VM_NAME}/${VM_NAME}.qcow2`
# Returns:
#   - $output file generated
#   - ${VM_NAME}.qcow2 file removed
#######################################
common::convert_to_vhd() {
  local output=${1:?- ***error*** \'output\' not set}
  local input="${WORKSPACE}/${VM_NAME}/${VM_NAME}.qcow2"
  qemu-img convert -f qcow2 -O vpc -o subformat=dynamic "${input}" "${output}"
  rm "${input}"
}

#######################################
# Retrieve installation media
# Exit if the file cannot be retrieved
# Globals:
#   CACHE_PATH
# Arguments:
#   ISO URL
#   ISO Checksum (SHA1 or SHA256)
#   Name of a variable which will contain the path to the downloaded file
# Returns:
#   Path to downloaded file
#######################################
common::retrieve_iso() {
  local iso_url="$1"
  local iso_checksum="$2"
  local -n iso_path="$3"
  common::echo_header "Retrieve installation media $(basename "${iso_url}")"

  mkdir -p "${CACHE_PATH}" || common::error "can't create ${CACHE_PATH}"

  # Build a cache file name with a hash from the URL to avoid conflict with
  # different images having the same name (typically boot ISOs)
  iso_path="${CACHE_PATH}/$(echo -n "${iso_url}" | sha1sum | cut -d ' ' -f 1)-$(basename "${iso_url}")"

  local checksum
  if [[ -f ${iso_path} || -L ${iso_path} ]]; then
    common::echo_message "using cached file ${iso_path}"
  elif [[ ${iso_url%%:*} == "file" ]]; then
    common::echo_message "using local file ${iso_url#file:}"
    [[ -f ${iso_url#file:} ]] || common::error "file does not exists"
    ln -s "${iso_url#file:}" "${iso_path}"
  else
    common::echo_message "downloading ${iso_url}"
    curl -L -s -o "${iso_path}" "${iso_url}" || common::error "can't retrieve ${iso_url}"
  fi
  local iso_checksum_type="sha1sum"
  [[ ${#iso_checksum} -eq 64 ]] && iso_checksum_type="sha256sum"
  checksum=$(${iso_checksum_type} "${iso_path}" | cut -d ' ' -f 1)
  [[ ${checksum} != "${iso_checksum}" ]] &&
    common::echo_message "checksum mismatch. Expected ${iso_checksum}, got ${checksum}" &&
    common::echo_message "after fixing the issue, you may have to remove the cached file ${iso_path}" &&
    common::error "terminating"
  true
}
