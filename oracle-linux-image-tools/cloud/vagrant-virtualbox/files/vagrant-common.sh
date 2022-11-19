#!/usr/bin/env bash
#
# Common scripts for vagrant provisioners
#
# Copyright (c) 2020, 2022 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

#######################################
# Configure Vagrant instance
# Globals:
#   ORACLE_RELEASE, UEK_RELEASE
# Arguments:
#   None
# Returns:
#   None
#######################################
vagrant::config()
{
  echo_message "Configure Vagrant"
  # Add vagrant user
  /usr/sbin/groupadd vagrant
  /usr/sbin/useradd vagrant -g vagrant -G wheel
  echo "%vagrant ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/vagrant
  chmod 0440 /etc/sudoers.d/vagrant
  restorecon /etc/sudoers.d/vagrant
  sed -i "s/^.*requiretty/#Defaults requiretty/" /etc/sudoers

  # sshd: disable password authentication and DNS checks
  if [[ "${ORACLE_RELEASE}" = "9" ]]; then
    cat > /etc/ssh/sshd_config.d/90-vagrant.conf <<-EOF
			PasswordAuthentication no
			UseDNS no
		EOF
  else
    ex -s /etc/ssh/sshd_config <<-EOF
			:%substitute/^#\?\(PasswordAuthentication\) .*$/\1 no/
			:%substitute/^#\?\(UseDNS\) .*$/\1 no/
			:update
			:quit
		EOF
  fi

  # For OL9 re-enable SHA1 as the vagrant embedded ssh client insists to use
  # SHA1 for RSA keys -- See hashicorp/vagrant#12344
  if [[ "${ORACLE_RELEASE}" = "9" ]]; then
    /bin/update-crypto-policies --set DEFAULT:SHA1
  fi

  cat >>/etc/sysconfig/sshd <<EOF

# Decrease connection time by preventing reverse DNS lookups
# (see https://lists.centos.org/pipermail/centos-devel/2016-July/014981.html
#  and man sshd for more information)
OPTIONS="-u0"
EOF

  # Default insecure vagrant key
  mkdir -p /home/vagrant/.ssh
  chmod 0700 /home/vagrant/.ssh
  echo "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key" >> /home/vagrant/.ssh/authorized_keys
  chmod 600 /home/vagrant/.ssh/authorized_keys
  chown -R vagrant:vagrant /home/vagrant/.ssh

  # Fix for issue #76, regular users can gain admin privileges via su
  ex -s /etc/pam.d/su <<'EOF'
/^account\s\+sufficient\s\+pam_succeed_if.so uid = 0 use_uid quiet$/
:append
# allow vagrant to use su, but prevent others from becoming root or vagrant
account         [success=1 default=ignore] \\
                                pam_succeed_if.so user = vagrant use_uid quiet
account         required        pam_succeed_if.so user notin root:vagrant
.
:update
:quit
EOF

  echo 'vag' > /etc/yum/vars/infra

  # Configure grub to wait just 1 second before booting
  if [[ "${ORACLE_RELEASE}" = "6" ]]; then
    sed -i 's/^timeout=[0-9]\+$/timeout=1/' /boot/grub/grub.conf
  else
    sed -i 's/^GRUB_TIMEOUT=[0-9]\+$/GRUB_TIMEOUT=1/' /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg
  fi

  # Blacklist the floppy module to avoid probing timeouts
  echo blacklist floppy > /etc/modprobe.d/nofloppy.conf
  chcon -u system_u -r object_r -t modules_conf_t /etc/modprobe.d/nofloppy.conf

  # Customize the initramfs
  if [[ "${ORACLE_RELEASE}" != "9" && "${UEK_RELEASE}" != "7" ]]; then
    # Enable VMware PVSCSI support for VMware Fusion guests.
    echo 'add_drivers+=" mptspi "' > /etc/dracut.conf.d/vmware-fusion-drivers.conf
    restorecon /etc/dracut.conf.d/vmware-fusion-drivers.conf
  fi
  # There's no floppy controller, but probing for it generates timeouts
  echo 'omit_drivers+=" floppy "' > /etc/dracut.conf.d/nofloppy.conf
  restorecon /etc/dracut.conf.d/nofloppy.conf
  # Regenerate initrd
  local current_kernel
  current_kernel=$(uname -r)
  ${DRACUT_CMD} -f "/boot/initramfs-${current_kernel}.img" "${current_kernel}"

  # Disabling firewalld on vagrant boxes
  if [[ "${ORACLE_RELEASE}" = "6" ]]; then
    service iptables stop
    chkconfig  iptables off
    service ip6tables stop
    chkconfig  ip6tables off
  else
    systemctl disable firewalld --now
  fi

  # Install additional release packages and enable repos
  yum install -y "${YUM_VERBOSE}" wget
  if [[ "${ORACLE_RELEASE}" = "7" ]]; then
    yum install -y "${YUM_VERBOSE}" oracle-softwarecollection-release-el7
    yum-config-manager --enable  ol7_addons >/dev/null
    yum-config-manager --enable  ol7_optional_latest >/dev/null
  elif [[ "${ORACLE_RELEASE}" = "6" ]]; then
    yum-config-manager --enable  ol6_addons >/dev/null
  fi

  # Install developer release packages and enable repos
  if [[ "${VAGRANT_DEVELOPER_REPOS,,}" = "yes" ]]; then
    if [[ "${ORACLE_RELEASE}" = "7" ]]; then
      yum install -y "${YUM_VERBOSE}" oracle-epel-release-el7 \
        oraclelinux-developer-release-el7
      yum-config-manager --enable  ol7_preview >/dev/null
      yum-config-manager --enable  ol7_developer >/dev/null
      yum-config-manager --enable  ol7_developer_EPEL >/dev/null
    elif [[ "${ORACLE_RELEASE}" = "6" ]]; then
      yum install -y "${YUM_VERBOSE}" oraclelinux-developer-release-el6
    elif  [[ "${ORACLE_RELEASE}" = "8" ]]; then
      dnf install -y oracle-epel-release-el8
    elif  [[ "${ORACLE_RELEASE}" = "9" ]]; then
      dnf install -y oracle-epel-release-el9
    fi
  fi

  # Add login banner
  echo "
Welcome to Oracle Linux Server release $(grep ^VERSION= /etc/os-release | grep -o "[0-9].[0-9]\+") (GNU/Linux $(uname -r))

The Oracle Linux End-User License Agreement can be viewed here:

  * /usr/share/eula/eula.en_US

For additional packages, updates, documentation and community help, see:

  * https://yum.oracle.com/
  " > /etc/motd

}

#######################################
# Cleanup module
# Globals:
#   ORACLE_RELEASE RESCUE_KERNEL
# Arguments:
#   None
# Returns:
#   None
#######################################
vagrant::cleanup()
{
  distr::remove_rpms usermode \
    rhn\* \
    m2crypto \
    iptables-services
  if [[ -z "${RESCUE_KERNEL}" || "${RESCUE_KERNEL,,}" = "no" ]]; then
    distr::remove_rpms dracut-config-rescue
  fi
}
