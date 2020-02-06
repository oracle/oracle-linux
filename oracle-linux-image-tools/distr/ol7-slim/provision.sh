#!/usr/bin/env bash
#
# Packer provisioning script for OL7
#
# Copyright (c) 1982-2019 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
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
  yum -C -y ${YUM_VERBOSE} remove "$@" --setopt="clean_requirements_on_remove=1"
}

#######################################
# Kernel configuration
# Globals:
#   DRACUT_CMD, KERNEL, UPDATE_TO_LATEST, YUM_VERBOSE
# Arguments:
#   None
# Returns:
#   None
#######################################
distr::kernel_config() {
  local kernel new_kernel old_kernel

  echo_message "Configure kernel: ${KERNEL^^}"
  # Add virtual drivers for xen,virtualbox and hyperv into the initrd using
  # dracut configuration files so that they get installed into the initrd
  # during fresh kernel installs.
  # This makes it is easy to move VM images between these virtual environments
  cat > /etc/dracut.conf.d/01-dracut-vm.conf <<-EOF
	add_drivers+=" xen_netfront xen_blkfront "
	add_drivers+=" virtio_blk virtio_net virtio virtio_pci virtio_balloon "
	add_drivers+=" hyperv_keyboard hv_netvsc hid_hyperv hv_utils hv_storvsc hyperv_fb "
	add_drivers+=" ahci libahci "
	EOF

  # Always install latest kernel
  if [[ "${KERNEL,,}" = "modrhck" ]]; then
    yum-config-manager --enable ol7_MODRHCK >/dev/null
  fi

  if [[ "${KERNEL,,}" = "uek" ]]; then
    kernel="kernel-uek"
    yum install -y ${YUM_VERBOSE} kernel-transition
    rpm -e kernel
  else
    kernel="kernel"
    rpm -e kernel-uek
  fi

  old_kernel=$(rpm -q ${kernel} --qf "%{VERSION}-%{RELEASE}")
  yum update -y ${YUM_VERBOSE} ${kernel}
  new_kernel=$(rpm -q ${kernel} --qf "%{VERSION}-%{RELEASE}\n" |
    sort --version-sort -r |
    head -n1)
  if [[ ${old_kernel} != ${new_kernel} ]]; then
    rpm -e "${kernel}-${old_kernel}"
  fi

  # Regenerate initrd
  new_kernel=$(rpm -q ${kernel} --qf "%{VERSION}-%{RELEASE}.%{ARCH}")
  ${DRACUT_CMD} -f "/boot/initramfs-${new_kernel}.img" "${new_kernel}"

  # Set correct default kernel
  sed -i -e 's/^DEFAULTKERNEL=.*/DEFAULTKERNEL=${kernel}/' /etc/sysconfig/kernel

  # Ensure grub is properly setup
  grub2-mkconfig -o /boot/grub2/grub.cfg
  grubby --set-default="/boot/vmlinuz-${new_kernel}"
}

#######################################
# Common configuration
# Globals:
#   UPDATE_TO_LATEST, YUM_VERBOSE
# Arguments:
#   None
# Returns:
#   None
#######################################distr::provision()
distr::common_cfg() {
  local service tty

  # Run yum update if flag is set to yes in image build page
  echo_message "Update image: ${UPDATE_TO_LATEST^^}"
  if [[ "${UPDATE_TO_LATEST,,}" = "yes" ]]; then
    yum update -y ${YUM_VERBOSE}
  elif [[ "${UPDATE_TO_LATEST,,}" = "security" ]]; then
    yum install -y ${YUM_VERBOSE} yum-plugin-security
    yum update --security -y ${YUM_VERBOSE}
  fi

  # TODO: Do we really want to use RH servers?
  sed -i -e '/^server .*/d' /etc/chrony.conf
  sed -i -e '/joining the pool/a \server 0.rhel.pool.ntp.org iburst \n\server 1.rhel.pool.ntp.org iburst \n\server 2.rhel.pool.ntp.org iburst \n\server 3.rhel.pool.ntp.org iburst' /etc/chrony.conf

  # If you want to remove rsyslog and just use journald, remove this!
  echo_message "Disabling persistent journal"
  rm -rf /var/log/journal/

  # setup systemd to boot to the right runlevel
  echo_message "Setting default runlevel to multiuser text mode"
  rm -f /etc/systemd/system/default.target
  ln -s /lib/systemd/system/multi-user.target /etc/systemd/system/default.target

  echo_message "Disable services"
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
    echo_message "    ${service}"
    systemctl disable ${service} 2>&1 || true
  done

  echo_message "Set rp_filter to loose mode"
  echo "net.ipv4.conf.default.rp_filter = 2" >> /etc/sysctl.conf

  echo_message "Set SELinux to Permissive"
  sed -i -e 's/^SELINUX[  ]*=.*/SELINUX=permissive/' /etc/selinux/config

  echo_message "Clear network persistent data"
  rm -f /etc/udev/rules.d/70-persistent-net.rules

  echo_message "Configure yum"
  # bypass update kernel-uek-headers
  echo "exclude=kernel-uek-headers" >> /etc/yum.conf
  # fix "Metadata file does not match checksum" for public-yum
  # https://forums.oracle.com/thread/2550364
  echo "http_caching=none" >> /etc/yum.conf

  echo_message "Enable login on serial console ports"
  for tty in "hvc0" "ttyS0" "ttyS0"
  do
    grep -q "${tty}" /etc/securetty ||  echo "${tty}" >>/etc/securetty
  done

  # TODO: simplify -- this is done as well in cleanup()!
  # 27601618 - set the machine-id file
  sed -i -e 's@^ExecStart=.*@ExecStart=/usr/bin/systemd-firstboot --prompt-locale --prompt-timezone --prompt-root-password --setup-machine-id@g' /usr/lib/systemd/system/systemd-firstboot.service

  echo_message "Remove unneeded RPMs"
  distr::remove_rpms \
    NetworkManager \
    NetworkManager-team \
    NetworkManager-config-server \
    NetworkManager-libnm \
    NetworkManager-tui
  # Remove firewalld; it is required to be present for install/image building.
  distr::remove_rpms firewalld
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
#######################################distr::provision()
distr::provision() {
  distr::kernel_config
  distr::common_cfg
}

#######################################
# Cleanup
# Globals:
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
  sed -i -e '/-p 50/d' /etc/sysconfig/iptables
  sed -i -e '/-p 51/d' /etc/sysconfig/iptables
  sed -i -e '/--dport 5353/d' /etc/sysconfig/iptables
  sed -i -e '/--dport 631/d' /etc/sysconfig/iptables
  sed -i -e '/-p 50/d' /etc/sysconfig/ip6tables
  sed -i -e '/-p 51/d' /etc/sysconfig/ip6tables
  sed -i -e '/--dport 5353/d' /etc/sysconfig/ip6tables
  sed -i -e '/--dport 631/d' /etc/sysconfig/ip6tables

  echo_message "Remove MAC addresses"
  for f in /etc/sysconfig/network-scripts/ifcfg-eth*; do
     [ -e "$f" ] && sed -i '/^HWADDR=/d' "$f"
  done

  echo_message "Yum cleanup"
  yum clean all --enablerepo=\*
  rm -rf /var/cache/yum/*
  rm -rf /var/lib/yum/*
  find /etc/ -name "./*.uln-*" -exec rm -rf {} \;

  # Cleanup and regenerate /etc/machine-id
  # Todo -- already done in provisioning!
  echo_message "Reset machine id"
  > /etc/machine-id
  grep -q setup-machine-id /usr/lib/systemd/system/systemd-firstboot.service
  [ $? -ne 0 ] && sed -i.old -e "/^ExecStart=/s/$/ --setup-machine-id/" /usr/lib/systemd/system/systemd-firstboot.service

  echo_message "Cleanup all log files"
  rm -f /var/log/anaconda.* /var/log/oraclevm-template.log
  rm -f /tmp/ks*
  rm -f /root/install.log /root/install.log.syslog /root/anaconda-ks.cfg
  > /etc/resolv.conf
  /bin/rm -f /etc/resolv.conf.*
  /bin/rm -f /var/lib/dhclient/*
  [ -e /var/log/acpid ] &&  > /var/log/acpid
  [ -e /var/log/messages ] && > /var/log/messages
  [ -e /var/log/btmp ] && > /var/log/btmp
  [ -e /var/log/grubby ] && > /var/log/grubby
  [ -e /var/log/secure ] &&  > /var/log/secure
  [ -e /var/log/wtmp ] && > /var/log/wtmp
  [ -e /var/log/boot.log ] &&  > /var/log/boot.log
  [ -e /var/log/dracut.log ] &&  > /var/log/dracut.log
  [ -e /var/log/tuned/tuned.log ] &&  > /var/log/tuned/tuned.log
  [ -e /var/log/maillog ] &&  > /var/log/maillog
  [ -e /var/log/lastlog ] &&  > /var/log/lastlog
  [ -e /var/log/yum.log ] &&  > /var/log/yum.log
  [ -e /var/log/ovm-template-config.log ] && rm -f /var/log/ovm-template-config.log
  /bin/rm -f /var/log/audit/audit.log*
  [ -e /var/log/audit/audit.log ] && > /var/log/audit/audit.log
  # cleanup ssh config files
  if [ -z "${SSH_KEY_FILE}" ]; then
    [ -d /root/.ssh ] && /bin/rm -fr /root/.ssh
  else
    find /root/.ssh -type f -not -name authorized_keys -delete
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
  [ -e  /root/.bash_history ] && > /root/.bash_history
  rm -f /root/.viminfo
  rm -rf /.autorelabel
  rm -rf /var/log/mail/statistics
  rm -rf /var/log/sa/*
  rm -rf /var/log/acpid /var/log/boot.log /var/log/cron /var/log/dmesg.* /var/log/ovm*
  rm -rf /poweroff
  rm -rf /tmp/*
  rm -f /etc/ssh/ssh_host_*
  rm -rf /var/lib/yum/*
  rm -rf /root/*
  rm -f /etc/udev/rules.d/70-persistent-net.rules
  rm -f /etc/udev/rules.d/70-persistent-cd.rules

  find /var/log -type f | while read f; do echo -ne '' > "$f"; done;
  find /etc/ -name "*.old" -exec rm -f {} \;
  rm -f /etc/sysconfig/network-scripts/ifcfg-enp*
  rm -rf /lost+found/*
  rm -rf /root/.vbox_version
  export HISTSIZE=0
  rm -f /var/log/ovm-template-config.log

  echo_message "Save list of installed packages"
  rpm -qa --qf "%{name}.%{arch}\n"  | sort -u > /home/rpm.list

  echo_message "Relabel SELinux"
  genhomedircon
  fixfiles -f -F relabel
  restorecon -R /
  history -c
  swapoff -a
}
