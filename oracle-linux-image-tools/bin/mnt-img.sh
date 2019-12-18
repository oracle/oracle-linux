#!/usr/bin/env bash
#
# Mount VM images
#
# Copyright (c) 1982-2019 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#
################################################################################
# The utility is a wrapper script that can map the partitions from vm image,
# and mount them to local directories.
# Usage:   mnt-img.sh  <image file> <mount point>
# Options: -u <image file> umount image file.
#          -l display all mounted images
#          -c umount all images
#          -v show version info.
#          -d display tracing msgs.
#          -h show this usage info.
################################################################################

case "$ORACLE_TRACE" in
  T) set -x;;
  *) ;;
esac

Usage() {
    cat <<EOF
Usage:   ${0##*/} <image file> <mount point>
Options: -u <image file> umount image file.
         -l display all mounted images
         -c umount all images
         -v show version info.
         -d display tracing msgs.
         -h show this usage info.
EOF
}

Error() {
  echo "ERROR: $1">&2
  echo
  [ "x$2" = "xu" ] && Usage
  exit 1
}

umount_img() {
    f=$1
    lp_device=$(grep "MOUNTED IMAGE" "$f"| awk -F: '{print $2}'| awk '{print $2}')
    image_file=$(grep "MOUNTED IMAGE" "$f"| awk -F: '{print $2}'| awk '{print $1}')
    mounteddirs=$(grep "MOUNTED DIR" "$f" | awk -F: '{print $2}' | awk '{print $2}')
    lvmgroups=$(grep "LVM GROUP" "$f" | awk -F: '{print $2}')
    if [ -f "$image_file" ]; then
      # umount first
      for dir_name in $mounteddirs; do
        if [ -d "$dir_name" ] && grep -q "$dir_name" /proc/mounts; then
          if ! umount "$dir_name"; then
            Error "Unable to umount $dir_name."
          fi
        fi
        # umount done, remove entry from database
        ftmp=$(mktemp /tmp/mntimg.XXXXX)
        grep -v "$dir_name" "$f" > "$ftmp"
        /bin/mv -f "$ftmp" "$f"
      done
      for vg_name in $lvmgroups; do
        vgchange -an "$vg_name" >/dev/null
      done
      # unmount any automounted paths
      for p in $(kpartx -l "$lp_device" |awk '{print $1}')
      do
        umount /dev/mapper/$p 2>/dev/null
      done
      kpartx -d "$lp_device"
      losetup -d "$lp_device"
    fi
    rm -f "$f"
}

list_mnt() {
    f=$1
    lp_device=$(grep "MOUNTED IMAGE" "$f"| awk -F: '{print $2}'| awk '{print $2}')
    image_file=$(grep "MOUNTED IMAGE" "$f"| awk -F: '{print $2}'| awk '{print $1}')
    if [ -f "$image_file" ]; then
      echo "--------------------------------------------------------------------"
      grep "MOUNTED IMAGE" "$f"
      # umount first
      grep "MOUNTED DIR" "$f"| while read line; do
        echo " |- $line"
      done
      grep "LVM GROUP" "$f"
    fi
}


#####################################################################

# define and env variables

VERSION=1.0.0b2

#default ACTION=mount
ACTION=mount

WORK_HOME=~/.mntimg
ID=0

# main ###############################################################
# handle arguments
while getopts ucldvh OPTION; do
    case "$OPTION" in
      u)
        ACTION=umount
        ;;
      c)
        ACTION=umountall
        ;;
      l)
        ACTION=listall
        ;;
      d)
        export ORACLE_TRACE=T
        set -v -x
        ;;
      v)
        echo $VERSION && exit 0
        ;;
      h)
        Usage && exit 0
        ;;
      *)
        Error "Wrong argument" u
        ;;
    esac
done
shift $((OPTIND - 1))
IMAGE_FILE="$1"
shift
MOUNT_POINT="$1"

# check arguments
if [ $ACTION = mount -o $ACTION = umount ]; then
  if [ ! -f "$IMAGE_FILE" ]; then
     Error "Image file $IMAGE_FILE does NOT exist" u
  fi

  if ! file "$IMAGE_FILE" | grep -q partition; then
     Error "Image file does NOT seem to have partitions."
  fi
fi

if [ $ACTION = mount ]; then
  if [ ! -d "$MOUNT_POINT" ]; then
     Error "Mount point directory $MOUNT_POINT does NOT exist" u
  fi
fi


# create working dir
mkdir -p $WORK_HOME

case "$ACTION" in
##########################################################################
# action mount
mount)

IMAGE_FILE=$(readlink -f "$IMAGE_FILE")
MOUNT_POINT=$(readlink -f "$MOUNT_POINT")
ID=$(echo "$IMAGE_FILE"| md5sum | awk '{print $1}')
if [ -f "$WORK_HOME/$ID" ]; then
  Error "$IMAGE_FILE has already been mounted"
fi
touch $WORK_HOME/"$ID"
#echo "Mounted Image:$IMAGE_FILE>$WORK_HOME/$ID"

# setup loop
LPDEVICE=$(losetup -f)
if ! losetup -f "$IMAGE_FILE"; then
  Error "setup loop device failed."
fi
# lock
echo "MOUNTED IMAGE:$IMAGE_FILE $LPDEVICE" > $WORK_HOME/"$ID"

# map device
if ! kpartx -a "$LPDEVICE" &>/dev/null; then
  losetup -d "$LPDEVICE"
  Error "kpartx map $LPDEVICE fail."
fi

mapped_devices=$(kpartx -l "$LPDEVICE" | grep "$LPDEVICE" | awk '{print $1}')
ct=1
for d in $mapped_devices; do
  mkdir -p "$MOUNT_POINT"/$ct
  file -sL /dev/mapper/"$d"
  # mount ext3, ext4, btrfs, xfs partitions
  if file -sL /dev/mapper/"$d" | egrep -q -i "ext3|ext4|btrfs|xfs"; then
     mount /dev/mapper/"$d" "$MOUNT_POINT"/$ct
     echo "MOUNTED DIR:/dev/mapper/$d $MOUNT_POINT/$ct" |tee -a $WORK_HOME/"$ID"
     ct=$((ct+1))
  else
     echo "/dev/mapper/$d not mounted - Unknown filesystem."
  fi

done
;;

############################################################################
umountall)
for f in $WORK_HOME/*; do
    umount_img "$f"
done
;;
############################################################################
# action umount
umount)
IMAGE_FILE=$(readlink -f "$IMAGE_FILE")
ID=$(echo "$IMAGE_FILE"| md5sum | awk '{print $1}')
if [ ! -f "$WORK_HOME/$ID" ]; then
  Error "$IMAGE_FILE has not been mounted"
fi
umount_img $WORK_HOME/"$ID"
;;
############################################################################
# list all mounted images
listall)
for f in $WORK_HOME/*; do
    list_mnt "$f"
done
;;
##########################################################################
*)
  Error "unexpected error" u
;;
esac
