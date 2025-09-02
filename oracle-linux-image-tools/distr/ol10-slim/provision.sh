#!/usr/bin/env bash
#
# Provisioning script for OL10
#
# Copyright (c) 2025 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# Description: provision an OL9 image. This module provides 3 functions,
# both are optional.
#   distr::provision: provision the instance
#   distr::cleanup: instance cleanup before shutdown
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

# Constants
readonly DRACUT_CMD="dracut --no-early-microcode --force"

#######################################
# Invoke dnf to remove packages
# Globals:
#   None
# Arguments:
#   List of packages to be removed
# Returns:
#   None
#######################################
distr::remove_rpms() {
  # clean_requirements_on_remove is default with dnf
  dnf -C -y remove "$@"
}

#######################################
# Kernel configuration
# Assume that we already run the latest selected kernel
# (Asserted in the kickstart file)
# Globals:
#   DRACUT_CMD, KERNEL
# Arguments:
#   None
# Returns:
#   None
#######################################
distr::kernel_config() {
  local kernel target_kernel

  # shellcheck disable=SC2153
  common::echo_message "Configure kernel: ${KERNEL^^}"

  # Note: there is no need to force drivers in intrd as dracut-config-generic
  # is installed

  # Configure repos and remove old kernels
  target_kernel=$(common::default_kernel)
  common::echo_message "Target kernel: ${target_kernel}"
  if [[ "${KERNEL,,}" = "uek" ]]; then
    kernel="kernel-uek"
    dnf config-manager --set-disabled ol10_UEKR\* || :
    dnf config-manager --set-enabled "ol10_UEKR${UEK_RELEASE}"
    common::remove_kernels kernel
    common::remove_kernels kernel-uek "${target_kernel}"
  else
    kernel="kernel"
    common::remove_kernels kernel-uek
    common::remove_kernels kernel "${target_kernel}"
  fi

  # Clean dnf cache which contains odd dependencies and prevents removal
  # of kernel modules
  rm -rf /var/cache/dnf/*
  rm -rf /var/lib/dnf/*
  if [[ ${KERNEL_MODULES,,} == "no" ]]; then
    common::echo_message "Removing kernel modules and linux firmware"
    dnf mark install "${kernel}-core"
    echo "exclude=${kernel}-core" >> /etc/dnf/dnf.conf
    distr::remove_rpms "${kernel}-modules" linux-firmware
    sed -i '/^exclude=/d' /etc/dnf/dnf.conf
  else
    common::echo_message "Ensure kernel modules are installed"
    dnf install -y ${kernel} linux-firmware
  fi

  # Regenerate initrd
  ${DRACUT_CMD} -f "/boot/initramfs-${target_kernel}.img" "${target_kernel}"

  # Ensure grub is properly setup
  grub2-mkconfig -o /boot/grub2/grub.cfg --update-bls-cmdline
  grubby --set-default="/boot/vmlinuz-${target_kernel}"
}

#######################################
# Common configuration
# Globals:
#   BUILD_INFO, PERMIT_ROOT_LOGIN, SELINUX, UPDATE_TO_LATEST
# Arguments:
#   None
# Returns:
#   None
#######################################
distr::configure() {
  local service tty

  # Directory to save build information
  mkdir -p "${BUILD_INFO}"

  # Run dnf update if flag is set to yes in image build page
  common::echo_message "Update image: ${UPDATE_TO_LATEST^^}"
  if [[ "${UPDATE_TO_LATEST,,}" = "yes" ]]; then
    dnf update -y
  elif [[ "${UPDATE_TO_LATEST,,}" = "security" ]]; then
    dnf update --security -y
  fi

  common::echo_message "sshd root login policy: ${PERMIT_ROOT_LOGIN}"
  cat > /etc/ssh/sshd_config.d/01-permitrootlogin.conf <<-EOF
		# root login policy when using ssh. Remove this file to revert to default.
		PermitRootLogin ${PERMIT_ROOT_LOGIN,,}
	EOF

  # SSSD profile needs clients
  if authselect current -r | grep -q '^sssd'; then
    common::echo_message "Installing SSSD client"
    dnf install -y sssd-client
  fi

  # If you want to remove rsyslog and just use journald, remove this!
  common::echo_message "Disabling persistent journal"
  rm -rf /var/log/journal/

  # setup systemd to boot to the right runlevel
  common::echo_message "Setting default runlevel to multi-user text mode"
  rm -f /etc/systemd/system/default.target
  ln -s /lib/systemd/system/multi-user.target /etc/systemd/system/default.target

  common::echo_message "Disable services"
  # shellcheck disable=SC2043
  for service in \
    kdump.service
  do
    # Most of these aren't enabled, errors are expected...
    common::echo_message "    ${service}"
    systemctl disable ${service} 2>&1 || true
  done

  common::echo_message "Set rp_filter to loose mode"
  echo "net.ipv4.conf.default.rp_filter = 2" >> /etc/sysctl.conf

  common::echo_message "Set SELinux to ${SELINUX^^}"
  sed -i -e "s/^SELINUX[  ]*=.*/SELINUX=${SELINUX,,}/" /etc/selinux/config
  if [[ ${SELINUX,,} != "enforcing" ]]; then
    # Relax SELinux for the provisioning as well
    setenforce Permissive
  fi

  common::echo_message "Clear network persistent data"
  rm -f /etc/udev/rules.d/70-persistent-net.rules

  common::echo_message "Configure dnf"
  # bypass update kernel-uek-headers
  echo "exclude=kernel-uek-headers" >> /etc/dnf/dnf.conf
  # fix "Metadata file does not match checksum" for public-yum
  # https://forums.oracle.com/thread/2550364
  echo "http_caching=none" >> /etc/dnf/dnf.conf

  common::echo_message "Enable login on serial console ports"
  for tty in "hvc0" "ttyS0" "ttyS0"
  do
    grep -q "${tty}" /etc/securetty ||  echo "${tty}" >>/etc/securetty
  done

  common::echo_message "Enable serial console: ${SERIAL_CONSOLE_RUNTIME^^}"
  if [[ "${SERIAL_CONSOLE_RUNTIME,,}" = "yes" ]]; then
    if ! grep "^GRUB_CMDLINE_LINUX.*console=ttyS0" /etc/default/grub; then
      # Only update if not already configured
      sed -i \
        -e 's/^\(GRUB_CMDLINE_LINUX=.*console=tty0\)/\1 console=ttyS0,115200n8/' \
        -e '/^GRUB_TERMINAL/d' \
        -e '/^GRUB_SERIAL_COMMAND/d' \
        /etc/default/grub
      cat >> /etc/default/grub <<-EOF
				GRUB_TERMINAL="serial console"
				GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
			EOF
      grub2-mkconfig -o /boot/grub2/grub.cfg --update-bls-cmdline
    fi
    systemctl enable serial-getty@ttyS0.service
  fi

  common::echo_message "Remove unneeded RPMs"
  distr::remove_rpms \
    polkit \
    polkit-pkla-compat
}

#######################################
# Provisioning
# Globals:
# Arguments:
#   None
# Returns:
#   None
#######################################
distr::provision() {
  common::ks_log
  distr::kernel_config
  distr::configure
}

#######################################
# Cleanup
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
distr::cleanup() {
  common::distr_cleanup
}
