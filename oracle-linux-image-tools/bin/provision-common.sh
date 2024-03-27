#!/usr/bin/env bash
#
# Common functions for provisionning the VM
#
# Copyright (c) 2024 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#

#######################################
# Print header
#######################################
common::echo_header() {
  echo "=== $* ==="
}

#######################################
# Print message
#######################################
common::echo_message() {
  echo "--- $* ---"
}

#######################################
# Print error message and exit
#######################################
common::error() {
  echo "--- $* ---" >&2
  exit 1
}

#######################################
# Print kickstart log
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
common::ks_log() {
  if [[ -f "/root/ks-post.log" ]]; then
    common::echo_message "Kickstart post log - Start"
    cat /root/ks-post.log
    rm /root/ks-post.log
    common::echo_message "Kickstart post log - End"
  fi
}

#######################################
# Return latest installed kernel
# Globals:
#   None
# Arguments:
#   "kernel" or "kernel-uek"
# Returns:
#   full version of the latest installed kernel
#######################################
common::latest_kernel() {
  local kernel=$1
  rpm -qa --qf "%{VERSION}-%{RELEASE}.%{ARCH}\n" "${kernel}" "${kernel}-core" | sort -V | tail -1
}

#######################################
# Return default kernel
# Return the kernel which will be used by default for this VM
# Globals:
#   KERNEL
# Arguments:
#   none
# Returns:
#   full version of the default kernel
#######################################
common::default_kernel() {
  local default_kernel
  default_kernel=$(grubby --default-kernel)
  echo "${default_kernel#*vmlinuz-}"
}

#######################################
# Remove RHCK or UEK kernels
# Globals:
#   None
# Arguments:
#   "kernel" or "kernel-uek"
#   kernel version to keep (optional)
# Returns:
#   None
#######################################
common::remove_kernels() {
  local kernel="$1"
  local keep="$2"
  local -a packages

  for flavor in "" "-core" "-modules" "-devel"; do
    if [[ -z ${keep} ]]; then
      mapfile -t packages < <(rpm -qa "${kernel}${flavor}")
    else
      mapfile -t packages < <(rpm -qa "${kernel}${flavor}" | grep -v "${keep}")
    fi
    if [[ ${#packages[@]} -gt 0 ]]; then
      distr::remove_rpms "${packages[@]}"
    fi
  done
}

#######################################
# Common distribution cleanup
# Globals:
#   BUILD_INFO, EXCLUDE_DOCS, ORACLE_RELEASE
# Arguments:
#   None
# Returns:
#   None
#######################################
common::distr_cleanup() {
  common::echo_message "Stoppping services"
  systemctl stop rsyslog || true
  systemctl stop auditd || true

  if [[ ${ORACLE_RELEASE} -lt 9 ]]; then
    common::echo_message "Remove leftover firewall rules"
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
  fi

  common::echo_message "Package manager cleanup"
  local pm
  if [[ ${ORACLE_RELEASE} -lt 8 ]]; then
    pm="yum"
  else
    pm="dnf"
  fi
  ${pm} -q repolist > "${BUILD_INFO}/repolist.txt"
  : > /etc/${pm}/vars/ociregion
  echo "oracle.com" > /etc/${pm}/vars/ocidomain
  rm -rf /var/cache/${pm}/*
  rm -rf /var/lib/${pm}/*
  find /etc/ -name "./*.uln-*" -exec rm -rf {} \;

  common::echo_message "Cleanup resolver files"
  : > /etc/resolv.conf
  /bin/rm -f /etc/resolv.conf.*

  # Rebuild rpmdb to save some space
  rpm --rebuilddb

  # Remove man and info pages
  common::echo_message "Exclude documentation: ${EXCLUDE_DOCS^^}"
  if [[ "${EXCLUDE_DOCS,,}" = "minimal" ]]; then
    rm -rf /usr/share/{man,info}
  fi

  common::echo_message "Misc cleanup"
  if [ -d /root/.vnc ]; then
    /bin/rm -f /root/.vnc/*.log
    /bin/rm -f /root/.vnc/passwd
  fi
  rm -f /root/.viminfo
  rm -rf /.autorelabel
  rm -rf /poweroff
  rm -f /etc/udev/rules.d/70-persistent-cd.rules
  find /etc/ -name "*.old" -exec rm -f {} \;
  rm -rf /var/lib/NetworkManager
  rm -rf /lost+found/*
  rm -rf /root/.vbox_version
  rm -rf /root/.gemrc /root/.gem
  export HISTSIZE=0

  common::echo_message "Save list of installed packages"
  rpm -qa --qf "%{name}.%{arch}\n"  | sort -u > "${BUILD_INFO}/pkglist.txt"
  rpm -qa --qf '"%{NAME}","%{EPOCHNUM}","%{VERSION}","%{RELEASE}","%{ARCH}"\n' | sort > "${BUILD_INFO}/pkglist.csv"
  common::default_kernel > "${BUILD_INFO}/kernel.txt"

  common::echo_message "lvm-system-devices"
  # OL8 virt-sysprep doesn't have this module
  rm -f /etc/lvm/devices/system.devices

  history -c
  swapoff -a
}
