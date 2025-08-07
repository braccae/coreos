#!/bin/bash

IMAGE_FILE=$1
DISK=$2

qemu-img convert -O raw -p $IMAGE_FILE $DISK

sync -f $DISK
sync $DISK

