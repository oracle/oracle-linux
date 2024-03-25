#!/usr/bin/env bash
#
# Provisioning script for OL7
#
# Copyright (c) 2019, 2024 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# Description: provision an OL7 image. This module provides 2 functions,
# both are optional.
#   distr::provision: provision the instance
#   distr::cleanup: instance cleanup before shutdown
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

# Constants
readonly DRACUT_CMD="dracut --no-early-microcode --force"

#######################################
# Invoke yum to remove packages
# Globals:
#   YUM_VERBOSE
# Arguments:
#   List of packages to be removed
# Returns:
#   None
#######################################
distr::remove_rpms() {
  yum -C -y "${YUM_VERBOSE}" remove "$@" --setopt="clean_requirements_on_remove=1"
}

#######################################
# Kernel configuration
# Assume that we already run the latest selected kernel
# (Asserted in the kickstart file)
# Globals:
#   DRACUT_CMD, KERNEL, LINUX_FIRMWARE, UEK_RELEASE, UPDATE_TO_LATEST, YUM_VERBOSE
# Arguments:
#   None
# Returns:
#   None
#######################################
distr::kernel_config() {
  local target_kernel

  # shellcheck disable=SC2153
  common::echo_message "Configure kernel: ${KERNEL^^}"

  # Configure repos and remove old kernels
  yum-config-manager --disable ol7_UEKR\* >/dev/null
  if [[ "${KERNEL,,}" = "modrhck" ]]; then
    yum-config-manager --enable ol7_MODRHCK >/dev/null
  fi

  if [[ "${KERNEL,,}" = "uek" ]]; then
    target_kernel=$(common::latest_kernel kernel-uek)
    common::echo_message "Target kernel: ${target_kernel}"
    yum-config-manager --enable "ol7_UEKR${UEK_RELEASE}" >/dev/null
    yum install -y "${YUM_VERBOSE}" kernel-transition
    common::remove_kernels kernel
    common::remove_kernels kernel-uek "${target_kernel}"
  else
    target_kernel=$(common::latest_kernel kernel)
    common::echo_message "Target kernel: ${target_kernel}"
    common::remove_kernels kernel-uek
    common::remove_kernels kernel "${target_kernel}"
  fi

  # Add virtual drivers for xen,virtualbox and hyperv into the initrd using
  # dracut configuration files so that they get installed into the initrd
  # during fresh kernel installs.
  # This makes it is easy to move VM images between these virtual environments
  local virtio modules
  modules=$(find "/lib/modules/${target_kernel}" -name "virtio*.ko*" -printf '%f\n')
  while read -r module; do
    virtio="${virtio} ${module%.ko*}"
  done <<<"${modules}"

  cat > /etc/dracut.conf.d/01-dracut-vm.conf <<-EOF
	add_drivers+=" xen_netfront xen_blkfront "
	add_drivers+=" ${virtio} "
	add_drivers+=" hyperv_keyboard hv_netvsc hid_hyperv hv_utils hv_storvsc hyperv_fb "
	add_drivers+=" ahci libahci "
	EOF

  # Regenerate initrd
  ${DRACUT_CMD} -f "/boot/initramfs-${target_kernel}.img" "${target_kernel}"

  # Ensure grub is properly setup
  grub2-mkconfig -o /boot/grub2/grub.cfg
  grubby --set-default="/boot/vmlinuz-${target_kernel}"

  common::echo_message "Linux firmware: ${LINUX_FIRMWARE^^}"
  if [[ "${LINUX_FIRMWARE,,}" = "no" ]]; then
    yum remove -y linux-firmware
  fi
}

#######################################
# Common configuration
# Globals:
#   BUILD_INFO, PERMIT_ROOT_LOGIN, SELINUX, UPDATE_TO_LATEST, YUM_VERBOSE
# Arguments:
#   None
# Returns:
#   None
#######################################
distr::common_cfg() {
  local service tty

  # Directory to save build information
  mkdir -p "${BUILD_INFO}"

  # Disable ol7_ociyum_config (Orabug 31106231)
  yum-config-manager --disable ol7_ociyum_config >/dev/null 2>&1

  # Run yum update if flag is set to yes in image build page
  common::echo_message "Update image: ${UPDATE_TO_LATEST^^}"
  if [[ "${UPDATE_TO_LATEST,,}" = "yes" ]]; then
    yum update -y "${YUM_VERBOSE}"
  elif [[ "${UPDATE_TO_LATEST,,}" = "security" ]]; then
    yum install -y "${YUM_VERBOSE}" yum-plugin-security
    yum update --security -y "${YUM_VERBOSE}"
  fi

  common::echo_message "sshd root login policy: ${PERMIT_ROOT_LOGIN}"
  ex -s /etc/ssh/sshd_config <<-EOF
		:%substitute/^#\?\(PermitRootLogin\) .*$/\1 ${PERMIT_ROOT_LOGIN,,}/
		:update
		:quit
	EOF

  # TODO: Do we really want to use RH servers?
  sed -i -e '/^server .*/d' /etc/chrony.conf
  sed -i -e '/joining the pool/a \server 0.rhel.pool.ntp.org iburst \n\server 1.rhel.pool.ntp.org iburst \n\server 2.rhel.pool.ntp.org iburst \n\server 3.rhel.pool.ntp.org iburst' /etc/chrony.conf

  # If you want to remove rsyslog and just use journald, remove this!
  common::echo_message "Disabling persistent journal"
  rm -rf /var/log/journal/

  # setup systemd to boot to the right runlevel
  common::echo_message "Setting default runlevel to multiuser text mode"
  rm -f /etc/systemd/system/default.target
  ln -s /lib/systemd/system/multi-user.target /etc/systemd/system/default.target

  common::echo_message "Disable services"
  for service in \
    kdump.service \
    ntpd.service \
    ntpdate.service \
    plymouth-quit-wait.service \
    plymouth-start.service \
    rhnsd.service \
    sendmail.service \
    sntp.service \
    syslog.target \
    NetworkManager.service
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

  common::echo_message "Configure yum"
  # bypass update kernel-uek-headers
  echo "exclude=kernel-uek-headers" >> /etc/yum.conf
  # fix "Metadata file does not match checksum" for public-yum
  # https://forums.oracle.com/thread/2550364
  echo "http_caching=none" >> /etc/yum.conf

  common::echo_message "Enable login on serial console ports"
  for tty in "hvc0" "ttyS0" "ttyS0"
  do
    grep -q "${tty}" /etc/securetty ||  echo "${tty}" >>/etc/securetty
  done

  common::echo_message "Remove unneeded RPMs"
  distr::remove_rpms \
    NetworkManager \
    NetworkManager-team \
    NetworkManager-config-server \
    NetworkManager-libnm \
    NetworkManager-tui

  # Remove others pkgs
  distr::remove_rpms \
    iwl7265-firmware \
    mozjs17 \
    polkit \
    polkit-pkla-compat \
    microcode_ctl
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
  distr::common_cfg
}

#######################################
# Cleanup
# Globals:
#   STRIP_LOCALES
# Arguments:
#   None
# Returns:
#   None
#######################################
distr::cleanup() {
  common::distr_cleanup

  common::echo_message "Strip locales: ${STRIP_LOCALES^^}"
  if [[ "${STRIP_LOCALES,,}" = "yes" ]]; then 
    # Remove unused locale files
    find /usr/share/locale -mindepth  1 -maxdepth 1 -type d \
      -not -name en_US -a -not -name C \
      -exec rm -rf {} +
  fi
}
