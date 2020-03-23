#!/usr/bin/env bash
#
# Creates OVF Envelope file for OL templates
#
# Copyright (c) 2019 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# Sample usage:
# mk-envelope -r OL7 -u 7 -v 1.0 -s 10
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

readonly PGM=$(basename "$0")
readonly PGM_DIR=$( cd "$(dirname "$0")" ; pwd -P )

help() {
  echo ""
  echo "Creates OVF Envelope file for OL templates"
  echo ""
  echo "Usage:"
  echo "  ${PGM} -r OL_RELEASE -u OL_UPDATE  -v VERSION -s DISK_SIZE"
  echo "      -r OL_RELEASE, OL7"
  echo "      -u OL_UPDATE, 0..9"
  echo "      -v VERSION, like 2.9"
  echo "      -s DISK_SIZE in GB, like 10"
  echo ""
}

init_parameter() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -r)
        shift
        if [[ -n $1 ]]; then
          OL_RELEASE="$1"
          shift
        fi
        ;;
      -u)
        shift
        if [[ -n $1 ]]; then
          OL_UPDATE="$1"
          shift
        fi
        ;;
      -v)
        shift
        if [[ -n $1 ]]; then
          IMAGE_VERSION="$1"
          shift
        fi
        ;;
      -s)
        shift
        if [[ -n $1 ]]; then
          CAPACITY=$(( $1 * 1024 * 1024 * 1024 ))
          shift
        fi
        ;;
      -h|-help|--help)
        help
        exit 0
        ;;
      *)
        help
        exit 0
        ;;
    esac
  done
}

#
# MAIN
#

if [[ $# -eq 0 ]]; then
  help
  exit 1
fi

init_parameter "$@"

# Output filename
readonly BASE_NAME="OVM_${OL_RELEASE}U${OL_UPDATE}_x86_64_PVHVM"
readonly SIZE=$(stat --printf=%s System.vmdk)

# Replace variables in template
sed -e "s/\\\${OL_RELEASE}/${OL_RELEASE}/" \
  -e "s/\\\${OL_UPDATE}/${OL_UPDATE}/" \
  -e "s/\\\${IMAGE_VERSION}/${IMAGE_VERSION}/" \
  -e "s/\\\${SIZE}/${SIZE}/" \
  -e "s/\\\${CAPACITY}/${CAPACITY}/" \
  < ${PGM_DIR}/OVM_TEMPLATE.ovf > "${BASE_NAME}.ovf"

# Create manifest file
rm -f "${BASE_NAME}.mf"
for file in "${BASE_NAME}.ovf" System.vmdk
do
  echo -n "SHA1(${file})= " >> "${BASE_NAME}.mf"
  sha1sum "${file}" | cut -d ' ' -f 1 >> "${BASE_NAME}.mf"
done

# Pack ova with manifest and without certificate
tar cf "${BASE_NAME}.ova" \
  "${BASE_NAME}.ovf" \
  "${BASE_NAME}.mf" \
  System.vmdk

# Cleanup
rm "${BASE_NAME}.ovf" "${BASE_NAME}.mf"

exit 0
