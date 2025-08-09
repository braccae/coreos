#!/bin/bash

rpm -e --nodeps zfs-fuse
dnf install -y "https://zfsonlinux.org/fedora/zfs-release-2-8$(rpm --eval "%{dist}").noarch.rpm"

dnf config-manager --disable zfs
dnf config-manager --enable zfs-kmod

dnf install -y zfs

echo zfs >/etc/modules-load.d/zfs.conf