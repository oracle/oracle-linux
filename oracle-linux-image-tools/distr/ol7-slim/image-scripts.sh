#!/usr/bin/env bash
#
# image scripts for OL7
#
# Copyright (c) 1982-2019 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# Description: this module provides a single function:
#   distr::image_cleanup: distribution specific actions to cleanup the image
#     This function is optional
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
  [[ "${ROOT_FS,,}" =~ ^(xfs)|(btrfs)$ ]] || error "ROOT_FS must be xfs or btrfs"
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
  local btrfs="\
part btrfs.01 --fstype="btrfs"  --ondisk=sda --size=4096 --grow\n\
btrfs none --label=btr_pool --data=single btrfs.01\n\
btrfs /    --subvol --name=root btr_pool\
"

  # Kickstart file is populated for xfs
  if [[ "${ROOT_FS,,}" = "btrfs" ]]; then
    sed -i -e 's!^part / .*$!'"${btrfs}"'!' "${WORKSPACE}/${KS_FILE}"
  fi

  # Pass kernel selection
  sed -i -e 's!^KERNEL=.*$!KERNEL='"${KERNEL}"'!' "${WORKSPACE}/${KS_FILE}"
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

  sudo chroot "${root_fs}" /bin/bash <<-EOF
	rm -f /var/log/wtmp
	touch /var/log/wtmp
	chcon -u system_u -r object_r -t wtmp_t /var/log/wtmp
	rm -f /var/log/audit/audit.log
	rm -f /var/log/tuned/tuned.log
	rm -f /var/log/lastlog
	touch /var/log/lastlog
	chmod 644 /var/log/lastlog
	chcon -u system_u -r object_r -t lastlog_t /var/log/lastlog
	chown root.utmp /var/log/wtmp
	chmod 664 /var/log/wtmp
	rm -rf /root/.gemrc /root/.gem
	rm -rf /var/spool/root /var/spool/mail/root
	rm -rf /var/lib/NetworkManager
	rm -rf /var/tmp/*
	rm -f /home/rpm.list
	EOF
}
