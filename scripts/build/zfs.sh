#!/usr/bin/env bash
set -euo pipefail

KERNEL_VERSION_FULL=$(ls /usr/lib/modules/)
KERNEL_VERSION=${KERNEL_VERSION_FULL%.*}

dnf install -y \
    gcc \
    make \
    autoconf \
    automake \ 
    libtool \
    git \
    libblkid-devel \
    libuuid-devel \
    libattr-devel \
    openssl-devel \
    zlib-devel \
    elfutils-libelf-devel \
    tree \
    fedora-packager \
    rpmdevtools \
    ncompress \
    libaio-devel \
    libffi-devel \
    libtirpc-devel \
    libudev-devel \
    python3-devel \
    kernel-devel-$KERNEL_VERSION

cd /tmp
curl -fLO https://github.com/openzfs/zfs/releases/download/zfs-${ZFS_VERSION}/zfs-${ZFS_VERSION}.tar.gz
tar -xvf zfs-${ZFS_VERSION}.tar.gz
cd zfs-${ZFS_VERSION}
./configure --with-linux=/usr/src/kernels/$KERNEL_VERSION_FULL
make -j1 rpm-utils rpm-kmod

KEYWORDS=("debug" "debuginfo" "devel" "debugsource" "src" "test")
for keyword in "${KEYWORDS[@]}"; do
    mkdir -p "/build/RPMS/$keyword"
    echo "Created directory /build/RPMS/$keyword"
done

for file in *.rpm; do
    if [[ -f "$file" ]]; then
        for keyword in "${KEYWORDS[@]}"; do
            if [[ "$file" == *"$keyword"* ]]; then
                mv "$file" "/build/RPMS/$keyword/"
                echo "Moved $file to /build/RPMS/$keyword/"
                break
            fi
        done
    fi
done

mv -v /tmp/zfs-${ZFS_VERSION}/*.rpm /build/RPMS/