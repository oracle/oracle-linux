#!/usr/bin/env bash
#
# image scripts for OL9
#
# Copyright (c) 2022, 2024 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# Description: this module provides the following function:
#   distr::validate: basic parameter validation
#   distr::kickstart: hook for kickstart file updates
# All functions are optional
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

#######################################
# Validate distribution parameters
# Globals:
#   KERNEL_MODULES, ROOT_FS, RESCUE_KERNEL, TMP_IN_TMPFS, EXCLUDE_DOCS
# Arguments:
#   None
# Returns:
#   None
#######################################
distr::validate() {
  [[ "${ROOT_FS,,}" =~ ^((xfs)|(btrfs)|(lvm))$ ]] || common::error "ROOT_FS must be xfs, btrfs or lvm"
  [[ "${ROOT_FS,,}" = "btrfs" ]] && common::echo_message "Note that for btrfs root filesystem you need to use an UEK boot ISO"
  [[ "${TMP_IN_TMPFS,,}" =~ ^((yes)|(no))$ ]] || common::error "TMP_IN_TMPFS must be yes or no"
  [[ "${RESCUE_KERNEL,,}" =~ ^((yes)|(no))$ ]] || common::error "RESCUE_KERNEL must be yes or no"
  [[ "${KERNEL_MODULES,,}" =~ ^((yes)|(no))$ ]] || common::error "KERNEL_MODULES must be yes or no"
  [[ "${EXCLUDE_DOCS,,}" =~ ^((yes)|(no)|(minimal))$ ]] || common::error "EXCLUDE_DOCS must be yes, no or minimal"
  readonly ROOT_FS TMP_IN_TMPFS RESCUE_KERNEL KERNEL_MODULES EXCLUDE_DOCS
}

#######################################
# Kickcstart fixup
# Globals:
#   AUTHSELECT, KERNEL, RESCUE_KERNEL, ROOT_FS
#   EXCLUDE_DOCS, TMP_IN_TMPFS
# Arguments:
#   kickstart file name
# Returns:
#   None
#######################################
distr::kickstart() {
  local ks_file="$1"

  local btrfs="\
part btrfs.01 --fstype=\"btrfs\"  --ondisk=sda --size=4096 --grow\n\
btrfs none  --label=btrfs_vol --data=single btrfs.01\n\
btrfs /     --subvol --name=root LABEL=btrfs_vol\n\
btrfs /home --subvol --name=home LABEL=btrfs_vol\
"
  local lvm="\
part pv.01 --ondisk=sda --size=4096 --grow\n\
volgroup vg_main pv.01\n\
logvol swap   --fstype=\"swap\" --vgname=vg_main --size=4096 --name=lv_swap\n\
logvol /      --fstype=\"xfs\"  --vgname=vg_main --size=4096 --name=lv_root --grow\
"

  # Kickstart file is populated for xfs
  if [[ "${ROOT_FS,,}" = "btrfs" ]]; then
    sed -i -e 's!^part / .*$!'"${btrfs}"'!' "${ks_file}"
  elif [[ "${ROOT_FS,,}" = "lvm" ]]; then
    sed -i -e '/^part swap/d' -e 's!^part / .*$!'"${lvm}"'!' "${ks_file}"
  fi

  # Pass kernel and rescue kernel selections
  sed -i -e 's!^KERNEL=.*$!KERNEL='"${KERNEL}"'!' "${ks_file}"
  sed -i -e 's!^RESCUE_KERNEL=.*$!RESCUE_KERNEL='"${RESCUE_KERNEL}"'!' "${ks_file}"

  # Override authselect if needed
  if [[ -n ${AUTHSELECT} ]]; then
    sed -i -e 's!^authselect .*$!authselect '"${AUTHSELECT}"'!' "${ks_file}"
  fi

  # Docs
  sed -i -e 's!^EXCLUDE_DOCS=.*$!EXCLUDE_DOCS='"${EXCLUDE_DOCS}"'!' "${ks_file}"
  if [[ "${EXCLUDE_DOCS,,}" = "yes" ]]; then
    sed -i -e 's!^%packages!%packages --excludedocs!' "${ks_file}"
  fi

  # /tmp in tmpfs
  sed -i -e "s!^TMP_IN_TMPFS=no!TMP_IN_TMPFS=${TMP_IN_TMPFS}!" "${ks_file}"
}
