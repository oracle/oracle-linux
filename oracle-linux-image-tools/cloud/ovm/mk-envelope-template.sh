#!/usr/bin/env bash
# shellcheck disable=2016
#
# Creates OVF Envelope template for OL templates
# This script requires the open-ovf tools
#
# Copyright (c) 2019,2020 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

set -e

readonly MKOVF=/usr/bin/mkovf
readonly RMOVF=/usr/bin/rmovf

# Template variables
readonly OL_RELEASE='${OL_RELEASE}'
readonly OL_UPDATE='${OL_UPDATE}'
readonly IMAGE_VERSION='${IMAGE_VERSION}'
readonly SIZE='${SIZE}'
readonly CAPACITY='${CAPACITY}'

# output filename
readonly OVF_FILE="OVM_TEMPLATE.ovf"

# ClassDesc for OL product
readonly CLASS_DESC="com.oracle.linux"
readonly PROD_INSTANCE="1"
# Virtual CPUs
readonly VCPUS=2
# Virtual memory (MB)
readonly VMEM=2048
# Virtual network
readonly VNET="xennet"
# VirtualSystem type (OL7 does not support PVM)
readonly VM_TYPE="PVHVM"
readonly VS_TYPE="DMTF:Oracle:X86:OracleVM_Xen:HVM_Linux"
# Arch and operatingSystem ID (We only build x86 64 bits)
readonly ARCH="x86_64"
readonly OSID="109"

readonly VSCID="OVM_${OL_RELEASE}U${OL_UPDATE}_${ARCH}_${VM_TYPE}"
readonly VSID="OVM_${OL_RELEASE}U${OL_UPDATE}_${ARCH}_${VM_TYPE}1"

# Initialize
"${MKOVF}" --init -f "${OVF_FILE}"

# File References and DiskSection (Need a System.vmdk dummy file!)
touch System.vmdk
"${MKOVF}" --efile -f "${OVF_FILE}" \
  -i "file1" \
  -n "System.vmdk" \
  -s "${SIZE}"
"${MKOVF}" --disk -f "${OVF_FILE}" \
  -i "system" \
  --capacity "${CAPACITY}" \
  --fileRef "file1" \
  --format "http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized" \
  --info "Virtual disks"

# NetworkSection
"${MKOVF}" --net -f "${OVF_FILE}" \
  -i "${VNET}" \
  --info "Logical networks used in the package" \
  --networkName ${VNET} \
  -d "The network that this service will be available on"

# VirtualSystemCollection
"${MKOVF}" --vsc -f "${OVF_FILE}"  -i "${VSCID}" \
  -m "Oracle Linux ${OL_RELEASE} update ${OL_UPDATE} for ${ARCH}"

# StartupSection
"${MKOVF}" --startup -f "${OVF_FILE}" \
  -m "Startup/Shutdown order for Virtual Systems" \
  -n "${VSID}" \
  -o "0" \
  -w \
  --id "${VSCID}"


# VirtualSystem
"${MKOVF}" --vs -f "${OVF_FILE}" \
  -i "${VSID}" \
  -m "Oracle Linux ${OL_RELEASE} update ${OL_UPDATE} for ${ARCH}" \
  --id "${VSCID}"

# ScalingSection
"${MKOVF}" --scaling -f "${OVF_FILE}" \
  --initial "1" \
  -m "Scaling info for VirtualSystem ${VSID}" \
  --id "${VSID}"
"${MKOVF}" --scaling -f "${OVF_FILE}" \
  --min "1" \
  -m "Scaling info for VirtualSystem ${VSID}" \
  --id "${VSID}"
"${MKOVF}" --scaling -f "${OVF_FILE}" \
  --max "64" \
  -m "Scaling info for VirtualSystem ${VSID}" \
  --id "${VSID}"

# ProductSection
"${MKOVF}" --product -f "${OVF_FILE}" \
  --info "Oracle Linux ${OL_RELEASE}.${OL_UPDATE} for ${ARCH}" \
  --comment "Operating System configuration parameters" \
  --product "Oracle Linux" --productVersion "${OL_RELEASE}.${OL_UPDATE}" \
  --fullVersion  "${OL_RELEASE}.${OL_UPDATE}_${IMAGE_VERSION}" \
  --classDesc ${CLASS_DESC} \
  --id "${VSID}" \
  --instance ${PROD_INSTANCE}

# OperatingSystemSection
"${MKOVF}" --os -f "${OVF_FILE}" \
  --info="Guest Operating System" --description="${OL_RELEASE}u${OL_UPDATE} for ${ARCH}" \
  --secID="${OSID}" \
  --id="${VSID}"

# Configuration properties for the product
# root-password
"${MKOVF}" --property -f "${OVF_FILE}" \
  --classDesc ${CLASS_DESC} \
  --key root-password \
  --type string \
  --userConfig true \
  --instance ${PROD_INSTANCE} \
  --password \
  --description "Specifies the root password"
#hostname
"${MKOVF}" --property -f "${OVF_FILE}" \
  --classDesc ${CLASS_DESC} \
  --key network.hostname \
  --type string \
  --userConfig true \
  --instance ${PROD_INSTANCE} \
  --description "Specifies the hostname for the appliance"
#bootproto
"${MKOVF}" --property -f "${OVF_FILE}" \
  --classDesc ${CLASS_DESC} \
  --key network.bootproto.0 \
  --type string \
  --userConfig true \
  --instance ${PROD_INSTANCE} \
  --description "Specifies the network protocol, dhcp/static, for device 0"
#ip address
"${MKOVF}" --property -f "${OVF_FILE}" \
  --classDesc ${CLASS_DESC} \
  --key network.ipaddr.0 \
  --type string \
  --userConfig true \
  --instance ${PROD_INSTANCE} \
  --description "Specifies the IP address"
#netmask
"${MKOVF}" --property -f "${OVF_FILE}" \
  --classDesc ${CLASS_DESC} \
  --key network.netmask.0 \
  --type string \
  --userConfig true \
  --instance ${PROD_INSTANCE} \
  --description "Specifies the netmask"
#gateway
"${MKOVF}" --property -f "${OVF_FILE}" \
  --classDesc ${CLASS_DESC} \
  --key network.gateway.0 \
  --type string \
  --userConfig true \
  --instance ${PROD_INSTANCE} \
  --description "Specifies the gateway"
#dns servers
"${MKOVF}" --property -f "${OVF_FILE}" \
  --classDesc ${CLASS_DESC} \
  --key network.dns-servers.0 \
  --type string \
  --userConfig true \
  --instance ${PROD_INSTANCE} \
  --description "Specifies the DNS on the deployed network"

#dns search domains
"${MKOVF}" --property -f "${OVF_FILE}" \
  --classDesc ${CLASS_DESC} \
  --key network.dns-search-domains.0 \
  --type string \
  --userConfig true \
  --instance ${PROD_INSTANCE} \
  --description "Specifies the DNS search domains"

# VirtualHardware
"${MKOVF}" --virthw -f "${OVF_FILE}" \
  --id "${VSID}" \
  --type ${VS_TYPE} \
  --info "Virtual Hardware: ${VMEM}MB, ${VCPUS} CPU(s), 1 disk, 1 nic" \
  --instanceID 1 \
  --elementName xen \
  --transport iso

"${MKOVF}" --resource -f "${OVF_FILE}" \
  --caption "Virtual CPU" \
  --description "Virtual CPU(s)" \
  --resourceID 1 \
  --resourceType 3 \
  --virtualQuantity ${VCPUS} \
  --elementName "Virtual_CPU"

"${MKOVF}" --resource -f "${OVF_FILE}" \
  --allocUnits "byte * 2^20" \
  --caption "${VMEM}MB memory" \
  --description "Memory size" \
  --resourceID 2 \
  --resourceType 4 \
  --virtualQuantity ${VMEM} \
  --elementName "Memory"

"${MKOVF}" --resource -f "${OVF_FILE}" \
  --caption "Ethernet controller 0" \
  --connection ${VNET} \
  --resourceID 3 \
  --resourceType 10 \
  --description "Ethernet controller 0" \
  --elementName "Ethernet_controller_0"

"${MKOVF}" --resource -f "${OVF_FILE}" \
  --address 0 \
  --caption "sataController0" \
  --resourceID 4 \
  --resourceType 20 \
  --resourceSubtype "AHCI" \
  --description "SATA controller 0" \
  --elementName "sataController0"


"${MKOVF}" --resource -f "${OVF_FILE}" \
  --caption "Disk System.vmdk" \
  --addressOnParent 0 \
  --hostResource "ovf:/disk/system" \
  --resourceID 5 \
  --resourceType 17 \
  --description "Disk System.vmdk" \
  --elementName "Disk_System.vmdk"

sed -i -e '/ResourceType>17/ i \                                         <rasd:Parent>4</rasd:Parent>' "$OVF_FILE"

other_disks=''
n=2
for d in ${other_disks}
do
  id=${d##*/}
  "${MKOVF}" --resource -f "${OVF_FILE}" \
    --caption "Disk ${id}" \
    --hostResource "ovf:/disk/${id%%.*}" \
    --resourceID $((n+4)) \
    --resourceType 17 \
    --description "Disk $id" \
    --elementName "Disk_${d}"
  n=$((n+1))
done

# cleanup, to use with current ovm-image-config
"${RMOVF}" --product \
  -c "${CLASS_DESC}" \
  -n "${CLASS_DESC}.${PROD_INSTANCE}" \
  -i -f "${OVF_FILE}"

rm System.vmdk

exit 0
