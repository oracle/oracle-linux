#!/bin/sh -e -x
#
# Sample usage:
# mk-envelope -r OL5 -u 7 -t PVM|PVHVM -a x86|x86_64 
#
#
# Copyright © 2019 Oracle Corp., Inc.  All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl
#

PROG=$(basename "${0}")
MKOVF=/usr/bin/mkovf
RMOVF=/usr/bin/rmovf
OVA=/usr/bin/ova

help()
{
        echo ""
        echo "Creates OVF Envelope file for OL templates"
        echo ""
        echo "Usage:"
        echo "  ${PROG} [ -r <OL release> ] [ -u <OL update> ] [ -a <architecture>] [ -t <vm type>]"
        echo "          -r <OL release>, OL7"
        echo "          -u <OL update>, 0..9 "
        echo "          -v <Template version>, like 2.9 "
        echo "          -a <architecture>, x86 or x86_64 "
        echo "          -t <vm type>, PVM - Paravirt, and "
        echo "                        PVHVM - Hardware Virtualized with Paravirt drivers"
        echo ""
}

init_parameter()
{
    while [ "X${1}" != "X" ]; do
        case "${1}" in
            -r)
                shift
                if [ "X${1}" != "X" ];then
                    OL_RELEASE=${1}
                    shift
                fi
                ;;
            -u)
                shift
                if [ "X${1}" != "X" ];then
                    OL_UPDATE=${1}
                    shift
                fi
                ;;
	    -v)
                shift
                if [ "X${1}" != "X" ];then
                    IMAGE_VERSION=${1}
                    shift
                fi
                ;;
            -a)
                shift
                if [ "X${1}" != "X" ];then
                    ARCH=$(echo "${1}" | tr "[:upper:]" "[:lower:]")
                    if [ "X${ARCH}X" = "Xi386X" ]; then
                        ARCH="x86" 
                    fi

                    shift
                fi
                ;;
            -t)
                shift
                if [ "X${1}" != "X" ];then
                    VM_TYPE=${1}
                    shift
                fi
                ;;
            -h|-help|--help)
                help
                exit 0
                ;;
            *)
                help
                exit 0
                ;;
        esac
    done
}

fail()
{ 
    echo "$@" >&2; 
    exit 1;
}


#
# MAIN
#
if [ "_$(id -u)" != "_0" ] ; then
    echo "You need to be root to execute this script!" >&2
    exit 1
fi

if [ "_${*}" = "_" ]; then
    help
    exit 1
fi

init_parameter "$@"

# output filename
OUTF="OVM_${OL_RELEASE}U${OL_UPDATE}_${ARCH}_${VM_TYPE}.ovf"
VSCID="OVM_${OL_RELEASE}U${OL_UPDATE}_${ARCH}_${VM_TYPE}"
VSID="OVM_${OL_RELEASE}U${OL_UPDATE}_${ARCH}_${VM_TYPE}1"

if [ ! -x ${MKOVF} ]; then
    fail "Cannot find mkovf, please check "
fi

# ClassDesc for OL product
CLASS_DESC="com.oracle.linux"
PROD_INSTANCE="1"
# Virtual CPUs
VCPUS=2
# Virtual memory (MB)
VMEM=2048
# Virtual network
VNET="xennet"
# VirtualSystem type
if [ "X${VM_TYPE}X" = "XPVMX" ] 
then
    VS_TYPE="DMTF:Oracle:X86:OracleVM_Xen:PVM_Linux"
elif [ "X${VM_TYPE}X" = "XPVHVMX" ]
then
    VS_TYPE="DMTF:Oracle:X86:OracleVM_Xen:HVM_Linux"
fi
# OperatingSystem ID
if [ "X${ARCH}X" = "Xx86X" ]; then
OSID="108"
elif [ "X${ARCH}X" = "Xx86_64X" ]; then
OSID="109"
fi

# other disks
other_disks=""

# Initialize 
${MKOVF} --init -f "${OUTF}"

# File References and DiskSection

size=$(stat --printf=%s System.vmdk)
capacity=$size
${MKOVF} --efile -f "${OUTF}" -i "file1" -n "System.vmdk" -s "$size"
${MKOVF} --disk -f "${OUTF}" -i "system" --capacity "$capacity" \
    --fileRef "file1" --format "http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized" \
    --info "Virtual disks"

for d in ${other_disks}
do
   gzip -c $d > tmpfile
   mv -f tmpfile $d
   size=$(stat --printf=%s "$d")
   capacity=$size
   id=${d##*/}
   ${MKOVF} --efile -f "${OUTF}" -i "${id%%.*}" -n "$id" -s "$size" -c "gzip"
   ${MKOVF} --disk -f "${OUTF}" -i "${id%%.*}" --capacity "$capacity" \
       --fileRef "${id%%.*}" --format "Raw disk image" \
       --info "Virtual disk"
done

# NetworkSection
${MKOVF} --net -f "${OUTF}" -i "${VNET}" \
   --info "Logical networks used in the package" --networkName ${VNET} \
   -d "The network that this service will be available on" 

# VirtualSystemCollection
${MKOVF} --vsc -f "${OUTF}"  -i "${VSCID}" \
  -m "Oracle Linux ${OL_RELEASE} update ${OL_UPDATE} for ${ARCH}"
  
# StartupSection
${MKOVF} --startup -f "${OUTF}" \
  -m "Startup/Shutdown order for Virtual Systems" \
  -n "${VSID}" -o "0" -w --id "${VSCID}"


# VirtualSystem
${MKOVF} --vs -f "${OUTF}"  -i "${VSID}" \
   -m "Oracle Linux ${OL_RELEASE} update ${OL_UPDATE} for ${ARCH}" \
   --id "${VSCID}"

# ScalingSection
${MKOVF} --scaling -f "${OUTF}" --initial "1" \
   -m "Scaling info for VirtualSystem ${VSID}" --id "${VSID}"
${MKOVF} --scaling -f "${OUTF}" --min "1" \
   -m "Scaling info for VirtualSystem ${VSID}" --id "${VSID}"
${MKOVF} --scaling -f "${OUTF}" --max "64" \
   -m "Scaling info for VirtualSystem ${VSID}" --id "${VSID}"
 
# ProductSection
${MKOVF} --product -f "${OUTF}" \
   --info "Oracle Linux ${OL_RELEASE}.${OL_UPDATE} for ${ARCH}" \
   --comment "Operating System configuration parameters" \
   --product "Oracle Linux" --productVersion "${OL_RELEASE}.${OL_UPDATE}" \
   --fullVersion  "${OL_RELEASE}.${OL_UPDATE}_${IMAGE_VERSION}" \
   --classDesc ${CLASS_DESC} --id "${VSID}" --instance ${PROD_INSTANCE}

# OperatingSystemSection
${MKOVF} --os -f "${OUTF}" \
  --info="Guest Operating System" --description="${OL_RELEASE}u${OL_UPDATE} for ${ARCH}" \
  --secID="${OSID}" \
  --id="${VSID}"

# Configuration properties for the product
# root-password
${MKOVF} --property -f "${OUTF}" --classDesc ${CLASS_DESC} \
   --key root-password --type string --userConfig true \
   --instance  ${PROD_INSTANCE}  --password \
   --description "Specifies the root password" 
#hostname
${MKOVF} --property -f "${OUTF}" --classDesc ${CLASS_DESC} \
   --key network.hostname --type string --userConfig true \
   --instance ${PROD_INSTANCE} \
   --description "Specifies the hostname for the appliance" 
#bootproto
${MKOVF} --property -f "${OUTF}" --classDesc ${CLASS_DESC} \
   --key network.bootproto.0 --type string --userConfig true \
   --instance ${PROD_INSTANCE} \
   --description "Specifies the network protocol, dhcp/static, for device 0" 
#ip address
${MKOVF} --property -f "${OUTF}" --classDesc ${CLASS_DESC} \
   --key network.ipaddr.0 --type string --userConfig true \
   --instance ${PROD_INSTANCE} \
   --description "Specifies the IP address" 
#netmask
${MKOVF} --property -f "${OUTF}" --classDesc ${CLASS_DESC} \
   --key network.netmask.0 --type string --userConfig true \
   --instance ${PROD_INSTANCE} \
   --description "Specifies the netmask" 
#gateway
${MKOVF} --property -f "${OUTF}" --classDesc ${CLASS_DESC} \
   --key network.gateway.0 --type string --userConfig true \
   --instance ${PROD_INSTANCE} \
   --description "Specifies the gateway" 
#dns servers
${MKOVF} --property -f "${OUTF}" --classDesc ${CLASS_DESC} \
   --key network.dns-servers.0 --type string --userConfig true \
   --instance ${PROD_INSTANCE} \
   --description "Specifies the DNS on the deployed network" 

#dns search domains
${MKOVF} --property -f "${OUTF}" --classDesc ${CLASS_DESC} \
   --key network.dns-search-domains.0 --type string --userConfig true \
   --instance ${PROD_INSTANCE} \
   --description "Specifies the DNS search domains" 

# VirtualHardware
${MKOVF} --virthw -f "${OUTF}" --id "${VSID}" --type ${VS_TYPE} \
   --info "Virtual Hardware: ${VMEM}MB, ${VCPUS} CPU(s), 1 disk, 1 nic" \
   --instanceID 1 --elementName xen --transport iso

${MKOVF} --resource -f "${OUTF}" --caption "Virtual CPU" \
   --description "Virtual CPU(s)" \
   --resourceID 1 --resourceType 3 --virtualQuantity ${VCPUS} \
   --elementName "Virtual_CPU"

${MKOVF} --resource -f "${OUTF}" --allocUnits "byte * 2^20" \
   --caption "${VMEM}MB memory" --description "Memory size" \
   --resourceID 2 --resourceType 4 --virtualQuantity ${VMEM} \
   --elementName "Memory"

${MKOVF} --resource -f "${OUTF}" \
   --caption "Ethernet controller 0" \
   --connection ${VNET}  --resourceID 3 --resourceType 10 \
   --description "Ethernet controller 0" \
   --elementName "Ethernet_controller_0"

${MKOVF} --resource -f "${OUTF}" \
   --address 0 \
   --caption "sataController0" \
   --resourceID 4 --resourceType 20 --resourceSubtype "AHCI" \
   --description "SATA controller 0" \
   --elementName "sataController0"


${MKOVF} --resource -f "${OUTF}" --caption "Disk System.vmdk" \
   --addressOnParent 0 \
   --hostResource "ovf:/disk/system" --resourceID 5 \
   --resourceType 17 --description "Disk System.vmdk" \
   --elementName "Disk_System.vmdk"

sed -i -e '/ResourceType>17/ i \                                         <rasd:Parent>4</rasd:Parent>' "$OUTF" 

n=2;
for d in ${other_disks} 
do
   id=${d##*/}
   ${MKOVF} --resource -f "${OUTF}" --caption "Disk ${id}" \
       --hostResource "ovf:/disk/${id%%.*}" --resourceID $((n+4)) \
       --resourceType 17 --description "Disk $id" \
       --elementName "Disk_${d}"
   n=$((n+1))
done

# cleanup, to use with current ovm-image-config
${RMOVF} --product -c "${CLASS_DESC}" -n "${CLASS_DESC}.${PROD_INSTANCE}" \
    -i -f "${OUTF}"

# create manifest file
${OVA} --manifest -f "${OUTF}"

# pack ova with manifest and without certificate
${OVA} --pack -m "${VSCID}".mf -r -f "${OUTF}"

exit 0
