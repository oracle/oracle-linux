#!/usr/bin/env bash
#
# image scripts for OL8
#
# Copyright (c) 2020 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# Description: this module provides the following function:
#   distr::validate: basic parameter validation
#   distr::kickstart: hook for kickstart file updates
#   distr::image_cleanup: distribution specific actions to cleanup the image
# All functions are optional
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

#######################################
# Validate distribution parameters
# Globals:
#   ROOT_FS
# Arguments:
#   None
# Returns:
#   None
#######################################
distr::validate() {
[[ "${ROOT_FS,,}" =~ ^(xfs)|(lvm)$ ]] || error "ROOT_FS must be xfs or lvm"
  readonly ROOT_FS
}

#######################################
# Kickcstart fixup
# Globals:
#   ROOT_FS
# Arguments:
#   kickstart file name
# Returns:
#   None
#######################################
distr::kickstart() {
  local ks_file="$1"

  local lvm="\
part pv.01 --ondisk=sda --size=4096 --grow\n\
volgroup vg_main pv.01\n\
logvol swap   --fstype=\"swap\" --vgname=vg_main --size=4096 --name=lv_swap\n\
logvol /      --fstype=\"xfs\"  --vgname=vg_main --size=4096 --name=lv_root --grow\
"

  # Kickstart file is populated for xfs
  if [[ "${ROOT_FS,,}" = "lvm" ]]; then
    sed -i -e '/^part swap/d' -e 's!^part / .*$!'"${lvm}"'!' "${ks_file}"
  fi

  # Pass kernel selection
  sed -i -e 's!^KERNEL=.*$!KERNEL='"${KERNEL}"'!' "${ks_file}"
}

#######################################
# Cleanup actions run directly on the image
# Globals:
#   WORKSPACE VM_NAME
# Arguments:
#   root filesystem directory
#   boot filesystem directory
# Returns:
#   None
#######################################
distr::image_cleanup() {
  local root_fs="$1"
  local boot_fs="$2"

  # Ensure we don't blindly cleanup local host!
  [[ -z ${root_fs} ]] && error "Undefined root filesystem"
  [[ -z ${boot_fs} ]] && error "Undefined boot filesystem"

  cp "${root_fs}"/home/rpm.list "${WORKSPACE}/${VM_NAME}/${VM_NAME}.pkglst"
  cp "${root_fs}"/home/rpm.csv "${WORKSPACE}/${VM_NAME}/pkglst.csv"
  cp "${root_fs}"/home/repolist.txt "${WORKSPACE}/${VM_NAME}/repolist.txt"
  cp "${root_fs}"/home/kernel.txt "${WORKSPACE}/${VM_NAME}/${VM_NAME}.kernel"

  sudo chroot "${root_fs}" /bin/bash <<-EOF
  : > /var/log/wtmp
  : > /var/log/lastlog
	rm -f /var/log/audit/audit.log
	rm -f /var/log/tuned/tuned.log
	rm -rf /root/.gemrc /root/.gem
	rm -rf /var/spool/root /var/spool/mail/root
	rm -rf /var/lib/NetworkManager
	rm -rf /var/tmp/*
	rm -f /home/rpm.list /home/rpm.csv /home/repolist.txt /home/kernel.txt
	EOF
}
