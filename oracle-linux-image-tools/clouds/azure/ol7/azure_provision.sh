#/bin/bash -e 
# Azure specific installation methods
#
# Copyright © 2019 Oracle Corp., Inc.  All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl
#

install_WALinuxAgent()
{
    curl http://public-yum.oracle.com/public-yum-ol7.repo -o /etc/yum.repos.d/public-yum-ol7.repo && DOWNLOADED_YUM_REPO=Yes
    disable_repo ol7_UEK_latest
    enable_repo ol7_addons
    disable_repo ol7_UEKR4
    enable_repo ol7_UEKR5
    enable_repo ol7_MODRHCK
    yum install -y parted python-pyasn1 hypervkvpd 
    yum -y install WALinuxAgent dnsmasq
    yum remove -y dracut-config-rescue
    rpm -e kernel-uek kernel-uek-firmware
    yum install -y kernel-uek kernel-uek-firmware
    new_uek="$(rpm -q kernel-uek --qf '%{VERSION}-%{RELEASE}.%{ARCH}')"
    ${DRACUT_CMD} -f "/boot/initramfs-${new_uek}.img" "${new_uek}"
    grubby --set-default "/boot/vmlinuz-${new_uek}"
    chkconfig --add waagent
    chkconfig waagent on
}

azure_cfg()
{
# simple eth0 config, again not hard-coded to the build hardware
    cat > /etc/sysconfig/network-scripts/ifcfg-eth0 << EOF
DEVICE=eth0
ONBOOT=yes
BOOTPROTO=dhcp
TYPE=Ethernet
USERCTL=no
PEERDNS=yes
IPV6INIT=no
NM_CONTROLLED=no
EOF

# Disable NetworkManager handling of the SRIOV interfaces
# Fix for Bug 16391: For Accelerated Networking Azure, use udev rule to prevent Hyper-V PCI device renaming
    cat << EOF > /etc/udev/rules.d/68-azure-sriov-nm-unmanaged.rules
# Accelerated Networking on Azure exposes a new SRIOV interface to the VM.
# This interface is transparently bonded to the synthetic interface,
# so NetworkManager should just ignore any SRIOV interfaces.
SUBSYSTEM=="net", DRIVERS=="hv_pci", ACTION=="add", ENV{NM_UNMANAGED}="1"
EOF

    # Disable some unneeded services by default
    systemctl disable wpa_supplicant 
    systemctl disable iptables
    systemctl disable ip6tables 
    systemctl enable network
    systemctl enable dnsmasq

    mkdir -m 0700 /var/lib/waagent
    mv /lib/udev/rules.d/75-persistent-net-generator.rules /var/lib/waagent/ 2>/dev/null
    touch /etc/udev/rules.d/75-persistent-net-generator.rules 2>/dev/null
 
    # Install Network Manager 
    yum -y install NetworkManager 

    grubby --update-kernel=ALL --args="console=tty1 console=ttyS0,115200n8 earlyprintk=ttyS0,115200 rootdelay=300 net.ifnames=0"
    sed -i 's/^\(GRUB_CMDLINE_LINUX\)=".*"$/\1="console=tty1 console=ttyS0,115200n8 earlyprintk=ttyS0,115200 rootdelay=300 net.ifnames=0"/g' /etc/default/grub
    sed -i 's/^#\(ClientAliveInterval\).*$/\1 180/g' /etc/ssh/sshd_config

    waagent -install
    # Configure waagent to add 2GB swap space for all instances by default
    sed -i -e "s/ResourceDisk.EnableSwap.*/ResourceDisk.EnableSwap=y/" /etc/waagent.conf
    sed -i -e "s/ResourceDisk.SwapSizeMB.*/ResourceDisk.SwapSizeMB=2048/" /etc/waagent.conf
    # update EULA
    curl ${AZURE_DBLICENSE} -o /usr/share/oraclelinux-release/EULA 
    curl ${AZURE_DBLICENSE} -o /usr/share/eula/eula.en_US

    # Add support for new yum repo scheme
    /usr/bin/ol_yum_configure.sh
}

install_azure()
{
        install_WALinuxAgent
        azure_cfg
}
