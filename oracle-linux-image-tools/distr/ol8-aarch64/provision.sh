#!/usr/bin/env bash
#
# Packer provisioning script for OL8 - aarch64
#
# Copyright (c) 2021,2022 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# Description: provision an OL8 image. This module provides 2 functions,
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
# Print kickstart log
# Globals:
# Arguments:
#   None
# Returns:
#   None
#######################################
distr::ks_log() {
  if [[ -f "/root/ks-post.log" ]]; then
    echo_message "Kickstart post log - Start"
    cat /root/ks-post.log
    rm /root/ks-post.log
    echo_message "Kickstart post log - End"
  fi
}

#######################################
# Kernel configuration
# Assume that we already run the latest selected kernel
# (Asserted in the kickstart file)
# Globals:
#   DRACUT_CMD, KERNEL, UPDATE_TO_LATEST
# Arguments:
#   None
# Returns:
#   None
#######################################
distr::kernel_config() {
  local current_kernel kernel kernels old_kernel

  # Ensure swap is properly formatted (UEK6/7 change)
  if [[ ${SETUP_SWAP,,} == "yes" ]]; then
    swapon -a || swapon -a --fixpgsz
  fi

  # shellcheck disable=SC2153
  echo_message "Configure kernel: ${KERNEL^^}"
  echo_message "Running kernel: $(uname -r)"

  # Note: there is no need to force drivers in intrd as dracut-config-generic
  # is installed

  # Remove old kernels
  dnf config-manager --disable ol8_UEKR\* || :
  if [[ ${UEK_RELEASE} != 6 ]]; then
    # UEK R6 doesn't have its own repo
    dnf config-manager --enable "ol8_UEKR${UEK_RELEASE}"
  fi

  current_kernel=$(uname -r)
  for kernel in "kernel-uek" "kernel-uek-core"; do
    if kernels=$(rpm -q ${kernel} --qf "%{VERSION}-%{RELEASE}.%{ARCH} "); then
      for old_kernel in $kernels; do
        if [[ ${old_kernel} != "${current_kernel}" ]]; then
          distr::remove_rpms "${kernel}-${old_kernel}"
        fi
      done
    fi
  done

  if [[ ${UEK_RELEASE} != 6 ]]; then
    if [[ ${KERNEL_MODULES,,} == "no" ]]; then
      echo_message "Removing kernel modules"
      distr::remove_rpms kernel-uek-modules
    else
      echo_message "Ensure kernel modules are installed"
      dnf install -y kernel-uek
    fi
  fi

  # Regenerate initrd
  ${DRACUT_CMD} -f "/boot/initramfs-${current_kernel}.img" "${current_kernel}"

  # Ensure grub is properly setup
  grub2-mkconfig -o /etc/grub2-efi.cfg
  grubby --set-default="/boot/vmlinuz-${current_kernel}"

  echo_message "Linux firmware: ${LINUX_FIRMWARE^^}"
  if [[ "${LINUX_FIRMWARE,,}" = "no" ]]; then
    echo_message "Removing linux firmware"
    distr::remove_rpms linux-firmware
  fi
}

#######################################
# Common configuration
# Globals:
#   UPDATE_TO_LATEST, BUILD_INFO
# Arguments:
#   None
# Returns:
#   None
#######################################
distr::common_cfg() {
  local service

  # Directory to save build information
  mkdir -p "${BUILD_INFO}"

  # Run dnf update if flag is set to yes in image build page
  echo_message "Update image: ${UPDATE_TO_LATEST^^}"
  if [[ "${UPDATE_TO_LATEST,,}" = "yes" ]]; then
    dnf update -y
  elif [[ "${UPDATE_TO_LATEST,,}" = "security" ]]; then
    dnf update --security -y
  fi

  # SSSD profile needs clients
  if authselect current -r | grep -q '^sssd'; then
    echo_message "Installing SSSD client"
    dnf install -y sssd-client
  fi

  # If you want to remove rsyslog and just use journald, remove this!
  echo_message "Disabling persistent journal"
  rm -rf /var/log/journal/

  # setup systemd to boot to the right runlevel
  echo_message "Setting default runlevel to multiuser text mode"
  rm -f /etc/systemd/system/default.target
  ln -s /lib/systemd/system/multi-user.target /etc/systemd/system/default.target

  echo_message "Disable services"
  # NetworkManager.service
  for service in \
    kdump.service \
    ntpd.service \
    ntpdate.service \
    plymouth-quit-wait.service \
    plymouth-start.service \
    rhnsd.service \
    sendmail.service \
    sntp.service \
    syslog.target
  do
    # Most of these aren't enabled, errors are expected...
    echo_message "    ${service}"
    systemctl disable ${service} 2>&1 || true
  done

  echo_message "Set rp_filter to loose mode"
  echo "net.ipv4.conf.default.rp_filter = 2" >> /etc/sysctl.conf

  echo_message "Set SELinux to ${SELINUX^^}"
  sed -i -e "s/^SELINUX[  ]*=.*/SELINUX=${SELINUX,,}/" /etc/selinux/config
  if [[ ${SELINUX,,} != "enforcing" ]]; then
    # Relax SELinux for the provisioning as well
    setenforce Permissive
  fi

  echo_message "Clear network persistent data"
  rm -f /etc/udev/rules.d/70-persistent-net.rules

  echo_message "Configure dnf"
  # bypass update kernel-uek-headers
  echo "exclude=kernel-uek-headers" >> /etc/dnf/dnf.conf
  # fix "Metadata file does not match checksum" for public-yum
  # https://forums.oracle.com/thread/2550364
  echo "http_caching=none" >> /etc/dnf/dnf.conf

  # TODO: simplify -- this is done as well in cleanup()!
  # 27601618 - set the machine-id file
  sed -i -e 's@^ExecStart=.*@ExecStart=/usr/bin/systemd-firstboot --prompt-locale --prompt-timezone --prompt-root-password --setup-machine-id@g' /usr/lib/systemd/system/systemd-firstboot.service

  echo_message "Remove unneeded RPMs"
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
  distr::ks_log
  distr::kernel_config
  distr::common_cfg
}

#######################################
# Cleanup
# Globals:
#   BUILD_INFO
# Arguments:
#   None
# Returns:
#   None
#######################################
distr::cleanup() {
  echo_message "Stoppping services"
  systemctl stop rsyslog || true
  systemctl stop auditd || true

  echo_message "Remove orabackup files"
  find /etc -name "*.orabackup*" -exec rm -rf {} \;
  find /boot -name "*.orabackup*" -exec rm -rf {} \;

  echo_message "Remove leftover firewall rules"
  if [[ -f /etc/sysconfig/iptables ]]; then
    sed -i -e '/-p 50/d' /etc/sysconfig/iptables
    sed -i -e '/-p 51/d' /etc/sysconfig/iptables
    sed -i -e '/--dport 5353/d' /etc/sysconfig/iptables
    sed -i -e '/--dport 631/d' /etc/sysconfig/iptables
  fi
  if [[ -f /etc/sysconfig/ip6tables ]]; then
    sed -i -e '/-p 50/d' /etc/sysconfig/ip6tables
    sed -i -e '/-p 51/d' /etc/sysconfig/ip6tables
    sed -i -e '/--dport 5353/d' /etc/sysconfig/ip6tables
    sed -i -e '/--dport 631/d' /etc/sysconfig/ip6tables
  fi

  echo_message "Remove MAC addresses"
  for f in /etc/sysconfig/network-scripts/ifcfg-eth*; do
     [ -e "$f" ] && sed -i '/^HWADDR=/d' "$f"
  done

  echo_message "Dnf cleanup"
  dnf -q repolist > "${BUILD_INFO}/repolist.txt"
  : > /etc/dnf/vars/ociregion
  rm -rf /var/cache/dnf/*
  rm -rf /var/lib/dnf/*
  find /etc/ -name "./*.uln-*" -exec rm -rf {} \;

  # Cleanup and regenerate /etc/machine-id
  # Todo -- already done in provisioning!
  echo_message "Reset machine id"
  : > /etc/machine-id
  if ! grep -q setup-machine-id /usr/lib/systemd/system/systemd-firstboot.service; then
    sed -i.old -e "/^ExecStart=/s/$/ --setup-machine-id/" /usr/lib/systemd/system/systemd-firstboot.service
  fi

  echo_message "Cleanup all log files"
  rm -f /var/log/anaconda.* /var/log/oraclevm-template.log
  rm -f /tmp/ks*
  rm -f /root/install.log /root/install.log.syslog /root/anaconda-ks.cfg
  : > /etc/resolv.conf
  /bin/rm -f /etc/resolv.conf.*
  /bin/rm -f /var/lib/dhclient/*
  [ -e /var/log/acpid ] &&  : > /var/log/acpid
  [ -e /var/log/messages ] && : > /var/log/messages
  [ -e /var/log/btmp ] && : > /var/log/btmp
  [ -e /var/log/grubby ] && : > /var/log/grubby
  [ -e /var/log/secure ] &&  : > /var/log/secure
  [ -e /var/log/wtmp ] && : > /var/log/wtmp
  [ -e /var/log/boot.log ] &&  : > /var/log/boot.log
  [ -e /var/log/dracut.log ] &&  : > /var/log/dracut.log
  [ -e /var/log/tuned/tuned.log ] &&  : > /var/log/tuned/tuned.log
  [ -e /var/log/maillog ] &&  : > /var/log/maillog
  [ -e /var/log/lastlog ] &&  : > /var/log/lastlog
  [ -e /var/log/dnf.log ] &&  : > /var/log/dnf.log
  [ -e /var/log/dnf.librepo.log ] &&  : > /var/log/dnf.librepo.log
  [ -e /var/log/dnf.rpm.log ] &&  : > /var/log/dnf.rpm.log
  [ -e /var/log/ovm-template-config.log ] && rm -f /var/log/ovm-template-config.log
  /bin/rm -f /var/log/audit/audit.log*
  [ -e /var/log/audit/audit.log ] && : > /var/log/audit/audit.log

  # Lock root user
  if [[ "${LOCK_ROOT,,}" = "yes" ]]; then
    passwd -d root
    passwd -l root
  fi

  # cleanup ssh config files
  if [ -z "${SSH_KEY_FILE}" ]; then
    [ -d /root/.ssh ] && /bin/rm -fr /root/.ssh
  else
    find /root/.ssh -type f -not -name authorized_keys -delete
  fi

  # Rebuild rpmdb to save some space
  rpm --rebuilddb

  # Remove man and info pages
  echo_message "Exclude documentation: ${EXCLUDE_DOCS^^}"
  if [[ "${EXCLUDE_DOCS,,}" = "minimal" ]]; then
    rm -rf /usr/share/{man,info}
  fi

  # cleanup vnc cache files
  if [ -d /root/.vnc ]; then
    /bin/rm -f /root/.vnc/*.log
    /bin/rm -f /root/.vnc/passwd
  fi

  rm -rf /var/log/cups/error_log
  rm -rf /var/log/setroubleshoot/setroubleshootd.log
  rm -rf /var/log/spooler
  # cleanup bash history
  [ -e  /root/.bash_history ] && : > /root/.bash_history
  rm -f /root/.viminfo
  rm -rf /.autorelabel
  rm -rf /var/log/mail/statistics
  rm -rf /var/log/sa/*
  rm -rf /var/log/acpid /var/log/boot.log /var/log/cron /var/log/dmesg.* /var/log/ovm*
  rm -rf /poweroff
  rm -rf /tmp/*
  rm -f /etc/ssh/ssh_host_*
  rm -rf /root/*
  rm -f /etc/udev/rules.d/70-persistent-net.rules
  rm -f /etc/udev/rules.d/70-persistent-cd.rules

  find /var/log -type f | while read -r f; do echo -ne '' > "$f"; done;
  find /etc/ -name "*.old" -exec rm -f {} \;
  rm -f /etc/sysconfig/network-scripts/ifcfg-enp*
  rm -rf /lost+found/*
  rm -rf /root/.vbox_version
  export HISTSIZE=0
  rm -f /var/log/ovm-template-config.log

  echo_message "Save list of installed packages"
  rpm -qa --qf "%{name}.%{arch}\n"  | sort -u > "${BUILD_INFO}/pkglist.txt"
  rpm -qa --qf '"%{NAME}","%{EPOCHNUM}","%{VERSION}","%{RELEASE}","%{ARCH}"\n' | sort > "${BUILD_INFO}/pkglist.csv"
  uname -r > "${BUILD_INFO}/kernel.txt"

  echo_message "Relabel SELinux"
  genhomedircon
  fixfiles -f -F relabel
  restorecon -R / || true
  history -c
  swapoff -a
}
