#!/usr/bin/env bash

# shellcheck disable=SC1090
#
# Create minimal Oracle Linux images
#
# Copyright (c) 2022 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# Description: creates minimal Oracle Linux images which can be used in cloud
# environment.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

#######################################
# Return 1 (true) if packaged using VirtualBox
# Globals:
#   PACKER_BUILDER
# Arguments:
#   None
# Returns:
#   1 -- packaged via VirtualBox
#   0 -- packaged via QEMU
#######################################
common::is_vbox() {
  test "${PACKER_BUILDER}" = "virtualbox-iso.x86-64"
  return
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
#   1: output file name (including .qcow extension)
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
# Convert disk image to VMDK format
# Globals:
#   None
# Arguments:
#   1: output file name (including .vmdk extension)
#   -: implicit use of `System.img`
# Returns:
#   - $output file generated
#   - System.img file removed
#######################################
common::convert_to_vmdk() {
  local output=${1:?- ***error*** \'output\' not set}
  if common::is_vbox ; then
    vboxmanage convertfromraw System.img --format VMDK "${output}" --variant Stream
  else
    qemu-img convert -f raw -O vmdk -o subformat=streamOptimized System.img "${output}"
  fi
  rm System.img
}

#######################################
# Convert disk image to VHD format
# Globals:
#   None
# Arguments:
#   1: output file name (including .vhd extension)
#   -: implicit use of `System.img`
# Returns:
#   - $output file generated
#   - System.img file removed
#######################################
common::convert_to_vhd() {
  local output=${1:?- ***error*** \'output\' not set}
  if common::is_vbox ; then
    vboxmanage convertfromraw System.img --format VHD "${output}"
  else
    qemu-img convert -f raw -O vpc -o subformat=dynamic System.img "${output}"
  fi
  rm System.img
}
