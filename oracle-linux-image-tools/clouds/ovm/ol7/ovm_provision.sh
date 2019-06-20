#/bin/bash -e 
# OVM specific installation methods
#
# Copyright © 2019 Oracle Corp., Inc.  All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl
#

ovm_cfg()
{
# simple eth0 config, again not hard-coded to the build hardware
cat > /etc/sysconfig/network-scripts/ifcfg-eth0 << EOF
DEVICE="eth0"
BOOTPROTO="dhcp"
ONBOOT="yes"
TYPE="Ethernet"
USERCTL="yes"
PEERDNS="yes"
IPV6INIT="no"
PERSISTENT_DHCLIENT="1"
EOF

    cat > /etc/default/grub  << EOF
GRUB_TIMEOUT=10
GRUB_HIDDEN_MENU_QUIET=false
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL="serial console"
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
GRUB_CMDLINE_LINUX="console=tty0"
GRUB_DISABLE_RECOVERY="true"
EOF
   serial_cfg
#Regenerate grub.cfg
grub2-mkconfig -o /boot/grub2/grub.cfg
}

install_vmapilibxenstore()
{
   curl http://public-yum.oracle.com/public-yum-ol7.repo -o /etc/yum.repos.d/public-yum-ol7.repo && DOWNLOADED_YUM_REPO=Yes
   enable_repo ol7_addons

   yum install -y libovmapi \
   libovmapi-devel \
   ovmd \
   ovm-template-config \
   ovm-template-config-authentication \
   ovm-template-config-datetime \
   ovm-template-config-firewall \
   ovm-template-config-network \
   ovm-template-config-selinux \
   ovm-template-config-ssh \
   ovm-template-config-system \
   ovm-template-config-user \
   python-simplejson \
   xenstoreprovider

  sed -i -e 's/^INITIAL_CONFIG.*/INITIAL_CONFIG=yes/' /etc/sysconfig/ovm-template-initial-config

   yum install -y libxenstore
}

install_ovm()
{
        install_vmapilibxenstore
        ovm_cfg
}

