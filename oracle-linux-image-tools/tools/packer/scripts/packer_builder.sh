#!/bin/bash -x
#
# Copyright © 2019 Oracle Corp., Inc.  All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl
#

. "$WORKSPACE/env.properties"

[ -z "$VM_NAME" ] || rm -rf "/u01/VirtualBox_VMs/$VM_NAME" 2>/dev/null
[ -d "${WORKSPACE}/${IMAGE_TYPE}" ] && rm -f "${WORKSPACE}/${IMAGE_TYPE}"/*

BUILD_PLATFORM="x86_64"
OS_INFO="Oracle_64"
ARCH=x86_64
TIMESTAMP=$(date +"%Y%m%d")
VM_NAME="${BUILD_REL}${BUILD_UPD}_${BUILD_PLATFORM}-b${BUILD_NUMBER}"
MEM_SIZE="8192"
CPU_NUM="4"
PREFIX_OUTPUT="vm-images"
VM_NAME="${BUILD_REL}${BUILD_UPD}_${BUILD_PLATFORM}-b${BUILD_NUMBER}"

OUTPUT_DIR="${WORKSPACE}/${PREFIX_OUTPUT}/${BUILD_REL}/${IMAGE_TYPE}/${BUILD_REL}${BUILD_UPD}-${TIMESTAMP}-b${BUILD_NUMBER}"

if [ -z "$DISK_SIZE" ]; then
    DISK_SIZE="15"
    if [ "X${IMAGE_TYPE}X" = "Xazure_imgX" ]; then
        DISK_SIZE="30"
    fi
fi

DISK_SIZE_MB=$(python -c "print str(round(${DISK_SIZE}*1024)).split('.')[0]")
SHUTDOWN_CMD="shutdown -P now; init 0"

PACKER_DIR="${PACKER_REPO}/tools/packer"
AZURE_DIR="${PACKER_REPO}/clouds/azure"
OVM_DIR="${PACKER_REPO}/clouds/ovm"
MNT_IMG="${PACKER_REPO}/tools/packer/scripts/mnt_img.sh"
CI_BUILD_REL=`echo $BUILD_REL | awk {'print tolower($0)'}`
cp "${PACKER_DIR}/${CI_BUILD_REL}/provision.sh" "${WORKSPACE}/provision.sh"
cp "${AZURE_DIR}/${CI_BUILD_REL}/azure_provision.sh" "${WORKSPACE}/azure_provision.sh"
cp "${OVM_DIR}/${CI_BUILD_REL}/ovm_provision.sh" "${WORKSPACE}/ovm_provision.sh"
cp "${PACKER_DIR}/scripts/uek_utils.sh" "${WORKSPACE}/uek_utils.sh"

SETUP_SWAP=yes
if [ "X${IMAGE_TYPE}X" = "Xazure_imgX" ]; then
    sed -i -e 's/^IMAGE_TYPE=.*/IMAGE_TYPE=azure_img/' "${WORKSPACE}/provision.sh"
    SETUP_SWAP=no
fi

if [ ! -z "$PROVISION_PATH" ]; then
    sed -i -e "s#^PROVISION_PATH=.*#PROVISION_PATH=\"${PROVISION_PATH}\"#" "${WORKSPACE}/provision.sh"
fi
if [ ! -z "$PROVISION_FILES" ]; then
    sed -i -e "s#^PROVISION_FILES=.*#PROVISION_FILES=\"${PROVISION_FILES}\"#" "${WORKSPACE}/provision.sh"
fi
if [ ! -z "$HOOK_NAME" ]; then
    sed -i -e "s#^HOOK_NAME=.*#HOOK_NAME=\"${HOOK_NAME}\"#" "${WORKSPACE}/provision.sh"
fi
if [ ! -z "$AZURE_DBLICENSE" ]; then
    sed -i -e "s#^AZURE_DBLICENSE=.*#AZURE_DBLICENSE=\"${AZURE_DBLICENSE}\"#" "${WORKSPACE}/provision.sh"
fi
if [ ! -z "$PROXY_URL" ]; then
    sed -i -e "s#^PROXY_URL=.*#PROXY_URL=\"${PROXY_URL}\"#" "${WORKSPACE}/provision.sh"
fi

# Set UPDATE_TO_LATEST to Yes or No in prosivion.sh based on input from build page
sed -i -e "s#^UPDATE_TO_LATEST=.*#UPDATE_TO_LATEST=\"${UPDATE_TO_LATEST}\"#" "${WORKSPACE}/provision.sh"
# Enable uek repo based on input from build page
sed -i -e "s#^ENABLE_UEK_REPO=.*#ENABLE_UEK_REPO=\"${ENABLE_UEK_REPO}\"#" "${WORKSPACE}/provision.sh"
#Update ENABLE_KSPLICE
sed -i -e "s#^ENABLE_KSPLICE.*#ENABLE_KSPLICE=\"${ENABLE_KSPLICE}\"#" "${WORKSPACE}/provision.sh"

# Virtualbox ISO only supported
BUILDER=virtualbox-iso

if [ X"${BUILDER}"X = "Xvirtualbox-isoX" ]; then
    if [ "X${ISO_TO_BASEIMG}X" = "XtrueX" ]; then
        sed -i -e 's/ISO_TO_BASEIMG=false/ISO_TO_BASEIMG=true/' "${WORKSPACE}/provision.sh"
        VM_NAME="${BUILD_REL}${BUILD_UPD}_${BUILD_PLATFORM}_BASEIMG"
        [ "$TEST_MOD" -eq 0 ] && VM_NAME="${BUILD_REL}${BUILD_UPD}_${BUILD_PLATFORM}_BASEIMG" || VM_NAME="${BUILD_REL}${BUILD_UPD}_${BUILD_PLATFORM}_BASEIMG_test"
        OUTPUT_DIR="/${WORKSPACE}/${PREFIX_OUTPUT}/${BUILD_REL}/${BUILD_REL}${BUILD_UPD}_BASEIMG-${TIMESTAMP}-b${BUILD_NUMBER}"
    fi


    # generating json file
    cat > "${WORKSPACE}/${BUILD_REL}${BUILD_UPD}-${BUILDER}-b${BUILD_NUMBER}.json" << _EOF
{
  "builders":
  [
    {
      "type": "${BUILDER}",
      "guest_os_type": "${OS_INFO}",
      "iso_url": "$ISO_URL",
      "iso_checksum": "$ISO_SHA1_CHECKSUM",
      "iso_checksum_type": "sha1",
      "output_directory": "$OUTPUT_DIR",
      "vm_name": "$VM_NAME",
      "shutdown_command": "$SHUTDOWN_CMD",
      "disk_size": "$DISK_SIZE_MB",
      "hard_drive_interface": "sata",
      "guest_additions_mode": "disable",
      "format": "ova",
      "headless": "true",
      "ssh_username": "root",
      "ssh_password": "ovsroot",
      "ssh_port": 22,
      "ssh_wait_timeout": "30m",
      "boot_wait": "20s",
      "boot_command":
      [
        "<tab> text ks=${KS_CONFIG} setup_swap=${SETUP_SWAP} <enter>"
      ],
      "vboxmanage":
      [
        ["modifyvm", "{{.Name}}", "--memory", ${MEM_SIZE}],
        ["modifyvm", "{{.Name}}", "--cpus", ${CPU_NUM}]
      ]
    }
  ],
  "provisioners":
  [
    {
       "type": "file",
       "source": "$WORKSPACE/uek_utils.sh",
       "destination": "/tmp/uek_utils.sh"
    },
    {
       "type": "file",
       "source": "$WORKSPACE/azure_provision.sh",
       "destination": "/tmp/azure_provision.sh"
    },
    {
       "type": "file",
       "source": "$WORKSPACE/ovm_provision.sh",
       "destination": "/tmp/ovm_provision.sh"
    },
    {
       "type": "shell",
       "script": "$WORKSPACE/provision.sh"
     }
  ]
}
_EOF

    packer build "${WORKSPACE}/${BUILD_REL}${BUILD_UPD}-${BUILDER}-b${BUILD_NUMBER}.json"
fi

[ -f "${OUTPUT_DIR}/$VM_NAME.ova" ] || exit 1
chmod +r  "${OUTPUT_DIR}/$VM_NAME.ova"



# CREATE PROD OVA FILE
if [ "X${ISO_TO_BASEIMG}X" = "XfalseX" ]; then
   cd "${OUTPUT_DIR}"
   tar -xf "$VM_NAME.ova"
   mv -f "${VM_NAME}"-disk*.vmdk System.vmdk
   # mount and cleanup img
   vbox-img convert --srcfilename System.vmdk --dstfilename System.img --srcformat VMDK --dstformat RAW
   sudo sh ${MNT_IMG} System.img .
   rootdir="2"
   df -T 2 | grep -sq btrfs
   if [ $? -eq 0 ]; then
       if [ "X${BUILD_REL}X" = "XOL7X" ]; then
           rootdir="2/root"
       fi
   fi
    sudo rm -f ${rootdir}/var/log/wtmp
    sudo touch ${rootdir}/var/log/wtmp
    sudo chcon -u system_u -r object_r -t wtmp_t ${rootdir}/var/log/wtmp
    sudo rm -f ${rootdir}/var/log/audit/audit.log
    sudo rm -f ${rootdir}/var/log/tuned/tuned.log
    sudo rm -f ${rootdir}/var/log/lastlog
    sudo touch ${rootdir}/var/log/lastlog
    sudo chmod 644 ${rootdir}/var/log/lastlog
    sudo chcon -u system_u -r object_r -t lastlog_t ${rootdir}/var/log/lastlog
    sudo chown root.utmp ${rootdir}/var/log/wtmp
    sudo chmod 664 ${rootdir}/var/log/wtmp
    sudo rm -rf /root/.gemrc /root/.gem |tee > /dev/null 2>&1
    sudo rm -rf /var/spool/root /var/spool/mail/root |tee > /dev/null 2>&1
    sudo rm -rf /var/lib/NetworkManager |tee > /dev/null 2>&1
    sudo rm -rf /var/tmp/* |tee > /dev/null 2>&1
    sudo cp ${rootdir}/home/rpm.list "${OUTPUT_DIR}/${IMAGE_TYPE}-${BUILD_REL}${BUILD_UPD}-${TIMESTAMP}-b${BUILD_NUMBER}.pkglst"
    sudo rm -f ${rootdir}/home/rpm.list
    if [ -d ${rootdir}/home/provision_files ]; then
	    sudo cp -r ${rootdir}/home/provision_files "${OUTPUT_DIR}/"
	    sudo rm -rf ${rootdir}/home/provision_files
    fi
    sudo sync && sync
    sudo fstrim 1
    sudo fstrim ${rootdir}
    sudo sh ${MNT_IMG} -u System.img
    sudo cp --sparse=always System.img System.img.sparse
    sudo mv -f System.img.sparse System.img
   rm -f System.vmdk 2> /dev/null
   rm -r 1 $rootdir 3 2>/dev/null
   if [ "X${IMAGE_TYPE}X" = "Xazure_imgX" ]; then
      sudo vboxmanage convertfromraw System.img --format VHD "OracleLinux-${BUILD_REL##OL}.${BUILD_UPD##U}-$BUILD_PLATFORM.vhd"
     rm -rf 2 ./*.ovf ./*.mf System.img > /dev/null 2>&1
     if [ "X${ISO_TO_BASEIMG}X" = "XfalseX" ]; then
         rm -rf ./*.ova
     fi
   else
     sudo vboxmanage convertfromraw System.img --format VMDK System.vmdk  --variant Stream
     rm -f ./System.img > /dev/null
     MK_ENVELOPE="${PACKER_REPO}/clouds/ovm/scripts/mk_envelope.sh"
     cp ${MK_ENVELOPE} mk_envelope.sh
     sudo sh mk_envelope.sh -r "${BUILD_REL}" -u "${BUILD_UPD##U}" -v "${IMAGE_VERSION}" -a "${BUILD_PLATFORM}" -t PVHVM
     sudo sh mk_envelope.sh -r "${BUILD_REL}" -u "${BUILD_UPD##U}" -v "${IMAGE_VERSION}" -a "${BUILD_PLATFORM}" -t PVM
     rm -f "$VM_NAME".* ./*.vmdk ./*.ovf
     rm -rf 2  ./*.vmdk ./*.ovf ./*.mf > /dev/null 2>&1
   fi
    sudo md5sum ./* | tee MD5SUM >/dev/null
   #Capture build parameter values
    sudo cp "$WORKSPACE/env.properties"  "${OUTPUT_DIR}/env.properties"
    sudo sed -i -e 's/^DISK_SIZE=.*/DISK_SIZE='${DISK_SIZE}'/' "${OUTPUT_DIR}/env.properties"
    sudo chmod +r ./*
   [ -d "${WORKSPACE}/${IMAGE_TYPE}" ] || mkdir -p "${WORKSPACE}/${IMAGE_TYPE}"
   cp -r -p "${OUTPUT_DIR}"/* "${WORKSPACE}/${IMAGE_TYPE}"
fi
wget --quiet --spider "${BUILD_URL}/submitDescription?description=${BUILD_REL}${BUILD_UPD}<br>${IMAGE_TYPE}<br>UEK=${ENABLE_UEK_REPO}<br>"
rm -f "${WORKSPACE}/${BUILD_REL}${BUILD_UPD}-${BUILDER}-b${BUILD_NUMBER}.json"
echo "Build output location:" > "${WORKSPACE}/mailcontents"
echo "${WORKSPACE}/${PREFIX_OUTPUT}/${BUILD_REL}/${IMAGE_TYPE}/${BUILD_REL}${BUILD_UPD}-${TIMESTAMP}-b${BUILD_NUMBER}" >> "${WORKSPACE}/mailcontents"
