#/bin/bash -e 
# the provisioner automatically defines certain commonly useful environmental variables: 
# PACKER_BUILD_NAME and PACKER_BUILDER_TYPE
#
# Copyright © 2019 Oracle Corp., Inc.  All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl
#

common_cfg()
{
    # run yum update
    old_uek=$(rpm -q kernel-uek --qf "%{VERSION}-%{RELEASE}")
    old_rh=$(rpm -q kernel --qf "%{VERSION}-%{RELEASE}")
    #Load loop driver to loopmount swap space to install wls
    modprobe loop

# Add ol7_MODRHCK to get the latest RH kernel security fixes for qualys scan
   echo -e "
[ol7_MODRHCK]
name=Latest RHCK with fixes from Oracle for Oracle Linux \$releasever (\$basearch)
baseurl=http://yum.oracle.com/repo/OracleLinux/OL7/MODRHCK/\$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=1
priority=20
enabled=1" >>  /etc/yum.repos.d/public-yum-ol7.repo

#Add virt drivers for xen,vbox and hyperv into the initrd using dracut conf files so that they get installed into the initrd during fresh kernel installs.
    #This makes it is easy to move VM images between these virt envs
    cat > /etc/dracut.conf.d/01-dracut-vm.conf   << EOF
add_drivers+=" xen_netfront xen_blkfront "
add_drivers+=" virtio_blk virtio_net virtio virtio_pci virtio_balloon "
add_drivers+=" hyperv_keyboard hv_netvsc hid_hyperv hv_utils hv_storvsc hyperv_fb "
add_drivers+=" ahci libahci "
EOF


    # Run yum update if flag is set to yes in image build page
    [ "$UPDATE_TO_LATEST" = "Yes" ] && yum -y update
    if [ "$UPDATE_TO_LATEST" = "Security" ]; then
        yum -y install yum-plugin-security
        yum -y --enablerepo=ol7_latest,ol7_MODRHCK --security update
    fi
    # Make sure crontabs and cronie are add back in
    yum install -y crontabs cronie
    new_uek=$(rpm -q kernel-uek --qf "%{VERSION}-%{RELEASE}\n"|sort --version-sort -r |head -n1)
    new_rh=$(rpm -q kernel --qf "%{VERSION}-%{RELEASE}\n"|sort --version-sort -r |head -n1)
    if [ "X${old_uek}X" != "X${new_uek}X" ];then
      rpm -qa | grep "${old_uek}" | xargs -i rpm -e --nodeps {}
      new_uek=$(rpm -q kernel-uek --qf "%{VERSION}-%{RELEASE}.%{ARCH}")
      ${DRACUT_CMD} -f "/boot/initramfs-${new_uek}.img" "${new_uek}"
    
    fi
    if [ "X${old_uek}X" = "X${new_uek}X" ];then
      ${DRACUT_CMD} -f "/boot/initramfs-${new_uek}.img" "${new_uek}"

    fi
    if [ "X${old_rh}X" != "X${new_rh}X" ];then
      rpm -qa | grep "${old_rh}" | xargs -i rpm -e --nodeps {}
      new_rh=$(rpm -q kernel --qf "%{VERSION}-%{RELEASE}.%{ARCH}")
      ${DRACUT_CMD} -f "/boot/initramfs-${new_rh}.img" "${new_rh}"
    fi

    if [ "X${old_rh}X" = "X${new_rh}X" ];then
      new_rh=$(rpm -q kernel --qf "%{VERSION}-%{RELEASE}.%{ARCH}")
      ${DRACUT_CMD} -f "/boot/initramfs-${new_rh}.img" "${new_rh}"
    fi

    # If you want to remove rsyslog and just use journald, remove this!
    echo -n "Disabling persistent journal"
    rmdir /var/log/journal/
    echo .
    # setup systemd to boot to the right runlevel
    echo -n "Setting default runlevel to multiuser text mode"
    rm -f /etc/systemd/system/default.target
    ln -s /lib/systemd/system/multi-user.target /etc/systemd/system/default.target
    echo .

    sed -i -e 's/^server .*/ /' /etc/chrony.conf
    sed -i -e '/joining the pool/ a \server 0.rhel.pool.ntp.org iburst \n\server 1.rhel.pool.ntp.org iburst \n\server 2.rhel.pool.ntp.org iburst \n\server 3.rhel.pool.ntp.org iburst' /etc/chrony.conf

    systemctl disable kdump.service ntpd.service ntpdate.service plymouth-quit-wait.service plymouth-start.service rhnsd.service sendmail.service sntp.service syslog.target NetworkManager.service

    find /etc/ -name "./*.uln-*" -exec rm -rf {} \;
    yum clean all
    rm -rf /var/cache/yum/*
    rm -rf /var/lib/yum/*
    find /etc -name "*.orabackup*" -exec rm -rf {} \;
    find /boot -name "*.orabackup*" -exec rm -rf {} \;
    # reconfigure after yum update
    sed -i -e '/-p 50/d' /etc/sysconfig/iptables
    sed -i -e '/-p 51/d' /etc/sysconfig/iptables
    sed -i -e '/--dport 5353/d' /etc/sysconfig/iptables
    sed -i -e '/--dport 631/d' /etc/sysconfig/iptables
    sed -i -e '/-p 50/d' /etc/sysconfig/ip6tables
    sed -i -e '/-p 51/d' /etc/sysconfig/ip6tables
    sed -i -e '/--dport 5353/d' /etc/sysconfig/ip6tables
    sed -i -e '/--dport 631/d' /etc/sysconfig/ip6tables
    echo "net.ipv4.conf.default.rp_filter = 2" >> /etc/sysctl.conf
    sed -i -e 's/^SELINUX[  ]*=.*/SELINUX=permissive/' /etc/selinux/config
    grep -sq "UTC=true" /etc/sysconfig/clock || echo "UTC=true" >> /etc/sysconfig/clock
    #Set timezone to UTC
    rm -f /etc/localtime && ln -s  /usr/share/zoneinfo/UTC /etc/localtime
    sed -i -e 's/^ZONE=.*/ZONE=\"UTC\"/' /etc/sysconfig/clock

    rm -f /etc/udev/rules.d/70-persistent-net.rules
    # bypass update kernel-uek-headers
    echo "exclude=kernel-uek-headers" >> /etc/yum.conf
    # fix "Metadata file does not match checksum" for public-yum
    # https://forums.oracle.com/thread/2550364
    echo "http_caching=none" >> /etc/yum.conf

    [ -d /u01 ] || mkdir /u01
    sed -i -e 's/^DEFAULTKERNEL=.*/DEFAULTKERNEL=kernel-uek/' /etc/sysconfig/kernel

    grep -q 'hvc0' /etc/securetty
    if [ ${?} != 0 ]; then
        echo "hvc0" >>/etc/securetty
    fi
    grep -q 'ttyS0' /etc/securetty
    if [ ${?} != 0 ]; then
        echo "ttyS0" >>/etc/securetty
    fi
   # generic localhost names
   cat > /etc/hosts << EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

EOF

   # 27601618 - set the machine-id file
   sed -i -e 's@^ExecStart=.*@ExecStart=/usr/bin/systemd-firstboot --prompt-locale --prompt-timezone --prompt-root-password --setup-machine-id@g' /usr/lib/systemd/system/systemd-firstboot.service

   yum -C -y remove NetworkManager NetworkManager-team NetworkManager-config-server NetworkManager-libnm NetworkManager-tui --setopt="clean_requirements_on_remove=1"
   # Remove firewalld; it is required to be present for install/image building.
   echo "Removing firewalld."
   yum -C -y remove firewalld --setopt="clean_requirements_on_remove=1"
   # Remove others pkgs 
   yum -C -y remove dnsmasq iwl7265-firmware mozjs17 polkit polkit-pkla-compat trousers nettle libproxy libmodman gsettings-desktop-schemas glib-networking gnutls libsoup libpcap ppp rdma libnl3 libnl3-cli jansson libteam teamd microcode_ctl --setopt="clean_requirements_on_remove=1"

}

serial_cfg()
{
   cat > /usr/lib/systemd/system/serial_console.service << EOF
#  This file is part of systemd.
#
#  systemd is free software; you can redistribute it and/or modify it
#  under the terms of the GNU Lesser General Public License as published by
#  the Free Software Foundation; either version 2.1 of the License, or
#  (at your option) any later version.

[Unit]
Description=Serial Getty on serial_console
Documentation=man:agetty(8) man:systemd-getty-generator(8)
Documentation=http://0pointer.de/blog/projects/serial-console.html
BindsTo=dev-serial_console.device
After=dev-%i.device systemd-user-sessions.service plymouth-quit-wait.service
After=rc-local.service

# If additional gettys are spawned during boot then we should make
# sure that this is synchronized before getty.target, even though
# getty.target didn't actually pull it in.
Before=getty.target
IgnoreOnIsolate=yes
Conflicts=serial-getty@ttyS0.service serial-getty@hvc0.service
ConditionPathIsSymbolicLink=/dev/serial_console

[Service]
ExecStart=-/sbin/agetty --keep-baud 115200,38400,9600 serial_console $TERM
Type=idle
Restart=always
UtmpIdentifier=serial_console
TTYPath=/dev/serial_console
TTYReset=yes
TTYVHangup=yes
KillMode=process
IgnoreSIGPIPE=no
SendSIGHUP=yes

[Install]
WantedBy=getty.target
EOF

    echo "KERNEL==\"ttyS0\", DEVPATH==\"/devices/pnp0/*\", SYMLINK+=\"serial_console\"" > /etc/udev/rules.d/50-udev.rules
    echo "KERNEL==\"hvc0\", DEVPATH==\"/devices/virtual/*\", SYMLINK+=\"serial_console\"" >> /etc/udev/rules.d/50-udev.rules
    systemctl enable serial_console.service 
    
}

removerpms()
{
  yum -C -y remove "$1" --setopt="clean_requirements_on_remove=1"
}

add_extra_u01()
{
    grep -sq "#UUID=#" /etc/fstab
    if [ $? -eq 0 ]; then
        pend=$(($(fdisk -ul /dev/sda | grep "total" | awk  '{print $(NF-1)}') - 1))
        pname=$(fdisk -ul /dev/sda | grep $pend | awk '{print $1}')
        if [ -b "${pname}" ]; then
            mkfs.ext4 "${pname}" 
	    UUID=$(blkid  "${pname}" | awk '{print $2}' | awk -F'"' '{print $2}')
            sed -i -e 's/#UUID=#/UUID='"${UUID}"'/' /etc/fstab
            mount -a
        fi
    fi
}

remote_provision()
{
    PROV_FILES_DIR=/home/provision_files
    [ -z "${PROVISION_PATH}" ] && return
    PROTO=$(echo "${PROVISION_PATH}" | awk -F ':' '{print $1}')
    case $PROTO in
        http|ftp)
        FETCH_CMD="curl -O"
        ;;
        *)
        FETCH_CMD="cp -p"
        ;;
    esac

    mkdir -p $PROV_FILES_DIR
    cd $PROV_FILES_DIR

    for file in $PROVISION_FILES; do
        if ! eval "${FETCH_CMD}" "${PROVISION_PATH}/$file";then
            echo "Error: fail to fetch ${PROVISION_PATH}/$file"
        fi
    done

    if [ -f "$PROV_FILES_DIR/$HOOK_NAME" ]; then
        chmod +x "$PROV_FILES_DIR/$HOOK_NAME"
        ./"$HOOK_NAME"
    fi

    cd -
}


cleanup()
{
    if [ "X${IMAGE_TYPE}X" = "Xazure_imgX" ];then
        waagent -force -deprovision
    fi

if [ "$(rpm -q kernel-uek --qf '%{VERSION}'|awk -F. '{print $1}')" -lt 4 ]
then
  cp -p /usr/share/grub/grub-mkconfig_lib /usr/share/grub/grub-mkconfig_lib.sav
  # we need to move uek3(3.8.x) before the RHCK(3.10.x), so need this sort way before run grub2-mkconfig
  sed -i -e 's/  version_test_gt_cmp=gt/  version_test_gt_cmp=lt/' /usr/share/grub/grub-mkconfig_lib
  grub2-mkconfig -o /boot/grub2/grub.cfg
  mv -f /usr/share/grub/grub-mkconfig_lib.sav /usr/share/grub/grub-mkconfig_lib
fi
  new_uek=$(rpm -q kernel-uek --qf "%{VERSION}-%{RELEASE}.%{ARCH}")
  grubby --set-default="/boot/vmlinuz-$new_uek"

  service rsyslog stop
  service auditd stop
  for f in /etc/sysconfig/network-scripts/ifcfg-eth*; do
     [ -e "$f" ] && sed -i '/^HWADDR=/d' "$f"
  done

  # Enable add_ons channel to workaround the issue with new repo split scheme
  yum-config-manager --enable ol7_addons

  echo "Cleaning old yum repodata."
  yum clean all

  #Cleanup and regenerate /etc/machine-id
  > /etc/machine-id
  grep -q setup-machine-id /usr/lib/systemd/system/systemd-firstboot.service
  [ $? -ne 0 ] && sed -i.old -e "/^ExecStart=/s/$/ --setup-machine-id/" /usr/lib/systemd/system/systemd-firstboot.service 

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
  [ -d /var/cache/yum ] && /bin/rm -fr /var/cache/yum/*
  # cleanup ssh cache files
  [ -d /root/.ssh ] && /bin/rm -fr /root/.ssh
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

   if [ "X${ISO_TO_BASEIMG}X" = "XfalseX" ];then
     if [ "X${IMAGE_TYPE}X" = "Xovm_imgX" ];then
       passwd -d root
     fi
   fi

   find /var/log -type f | while read f; do echo -ne '' > "$f"; done;
   find /etc/ -name "*.old" -exec rm -f {} \;
   rm -f /etc/sysconfig/network-scripts/ifcfg-enp*
   rm -rf /lost+found/*
   rm -rf /root/.vbox_version
   export HISTSIZE=0
   rm -f /var/log/ovm-template-config.log
   # list installed pkg
   echo "list installed pkgs to jenkins console"
   rpm -qa --qf "%{name}.%{arch}\n"  | sort -u
   # relabel selinux
   genhomedircon
   # Collect list of installed RPM to /tmp/rpm.list . This file will be deleted later by packer_builder.sh
   rpm -qa >  /home/rpm.list
   fixfiles -f -F relabel
   restorecon -R /
   history -c
   swapoff -a

}

enable_UEKrepo()
{
  if [ "X${ENABLE_UEK_REPO}X" != "XdefaultX" ]; then
     repo_name=$(match_UEKrepo "${ENABLE_UEK_REPO}")
     if [ "X${repo_name}X" != "XdefaultX" ]; then
         current_uek=$(installed_UEK)
         current_repo=$(match_UEKrepo "${current_uek}")
         if [[ ${current_uek##UEK} -ne ${ENABLE_UEK_REPO##UEK} ]]; then
             if [ "X${DOWNLOADED_YUM_REPO}X" != "XYesX" ]; then
                 curl http://public-yum.oracle.com/public-yum-ol7.repo -o /etc/yum.repos.d/public-yum-ol7.repo
             fi
             enable_repo "${repo_name}"
             disable_repo "${current_repo}"
             enable_repo ol7_MODRHCK
	     if [ "X${ENABLE_UEK_REPO}X" != "XUEK5X" ]; then
               disable_repo ol7_UEKR5
	     fi
             rpm -e kernel-uek 
             rpm -e kernel-uek-firmware
             yum install -y kernel-uek kernel-uek-firmware
             new_uek=$(rpm -q kernel-uek --qf "%{VERSION}-%{RELEASE}.%{ARCH}")
             ${DRACUT_CMD} -f "/boot/initramfs-${new_uek}.img" "${new_uek}"
             grubby --set-default "/boot/vmlinuz-${new_uek}"
         fi
     fi
  fi
}


provision()
{
  common_cfg
  if [ "X${ISO_TO_BASEIMG}X" = "XfalseX" ];then
      if [ "X${IMAGE_TYPE}X" = "Xazure_imgX" ]; then
        install_azure
      else
        install_ovm
      fi
  fi
  enable_UEKrepo
  add_extra_u01
  remote_provision
  cleanup
}

#MAIN
IMAGE_TYPE="ovm_img"
ISO_TO_BASEIMG=false
PROVISION_PATH=""
PROVISION_FILES=""
HOOK_NAME="packer_hook"
UPDATE_TO_LATEST="Yes"
ENABLE_UEK_REPO="default"
ENABLE_KSPLICE="No"
DOWNLOADED_YUM_REPO=""
AZURE_DBLICENSE=""
PROXY_URL=""
DRACUT_CMD="dracut --add-drivers hyperv_keyboard --add-drivers hv_netvsc --add-drivers hid_hyperv --add-drivers hv_utils --add-drivers hv_storvsc --add-drivers hyperv_fb --add-drivers virtio_blk --add-drivers virtio_net --add-drivers virtio --add-drivers virtio_pci --add-drivers virtio_balloon --add-drivers xen_netfront --add-drivers xen_blkfront --no-early-microcode --force"

if [ ! -z "$PROXY_URL" ]; then
	export http_proxy=${PROXY_URL}
	export ftp_proxy=${PROXY_URL}
	export https_proxy=${PROXY_URL}
	export sftp_proxy=${PROXY_URL}
fi

[ -f /tmp/uek_utils.sh ] && . /tmp/uek_utils.sh
[ -f /tmp/azure_provision.sh ] && . /tmp/azure_provision.sh
[ -f /tmp/ovm_provision.sh ] && . /tmp/ovm_provision.sh

case $PACKER_BUILDER_TYPE in
    virtualbox-iso|virtualbox-ovf)
        provision
        ;;
esac
