#!/bin/bash

OUTPUT_DIR=$1
CONFIG=$2
IMAGE_TAG=$3

podman pull ghcr.io/braccae/coreos:$IMAGE_TAG

podman run \
    --rm \
    -it \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v $CONFIG:/config.toml:ro \
    -v $OUTPUT_DIR/$IMAGE_TAG:/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type qcow2 \
    --use-librepo=True \
    --rootfs btrfs \
    ghcr.io/braccae/coreos:$IMAGE_TAG
