# FROM quay.io/fedora/fedora-bootc:42 AS builder

# ARG ZFS_VERSION="2.3.4"

# # # Extract kernel version from container's embedded kernel
# # # https://bootc-dev.github.io/bootc/bootc-images.html#kernel
# RUN <<EOT
# #!/usr/bin/env bash
# set -euo pipefail

# KERNEL_VERSION_FULL=$(ls /usr/lib/modules/)
# KERNEL_VERSION=${KERNEL_VERSION_FULL%.*}

# dnf install -y \
#     gcc \
#     make \
#     autoconf \
#     automake \ 
#     libtool \
#     git \
#     libblkid-devel \
#     libuuid-devel \
#     libattr-devel \
#     openssl-devel \
#     zlib-devel \
#     elfutils-libelf-devel \
#     tree \
#     fedora-packager \
#     rpmdevtools \
#     ncompress \
#     libaio-devel \
#     libffi-devel \
#     libtirpc-devel \
#     libudev-devel \
#     python3-devel \
#     kernel-devel-$KERNEL_VERSION \

# cd /tmp
# curl -fLO https://github.com/openzfs/zfs/releases/download/zfs-${ZFS_VERSION}/zfs-${ZFS_VERSION}.tar.gz
# tar -xvf zfs-${ZFS_VERSION}.tar.gz
# cd zfs-${ZFS_VERSION}
# ./configure --with-linux=/usr/src/kernels/$KERNEL_VERSION_FULL
# make -j1 rpm-utils rpm-kmod

# KEYWORDS=("debug" "debuginfo" "devel" "debugsource" "src" "test")
# for keyword in "${KEYWORDS[@]}"; do
#     mkdir -p "/build/RPMS/$keyword"
#     echo "Created directory /build/RPMS/$keyword"
# done

# for file in *.rpm; do
#     if [[ -f "$file" ]]; then
#         for keyword in "${KEYWORDS[@]}"; do
#             if [[ "$file" == *"$keyword"* ]]; then
#                 mv "$file" "/build/RPMS/$keyword/"
#                 echo "Moved $file to /build/RPMS/$keyword/"
#                 break
#             fi
#         done
#     fi
# done

# mv -v /tmp/zfs-${ZFS_VERSION}/*.rpm /build/RPMS/

# EOT

FROM quay.io/fedora/fedora-bootc:42
LABEL containers.bootc 1

RUN dnf5 install -y dnf5-plugins \
    && dnf clean all

RUN dnf5 config-manager addrepo \
    --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo

RUN dnf5 install -y \
    qemu-guest-agent \
    tailscale \
    firewalld \
    sqlite \
    borgmatic \
    fuse \
    rclone \
    rsync \
    cockpit-system \
    cockpit-bridge \
    cockpit-networkmanager \
    cockpit-podman \
    cockpit-ostree \
    cockpit-selinux \
    cockpit-storaged \
    cockpit-files \
    python3-psycopg2 \
    xdg-user-dirs \
    python3-pip \
    && dnf clean all

RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="/usr/bin" sh
# RUN /usr/bin/uv pip install --system packaging

COPY scripts/build /tmp/build_scripts
RUN bash /tmp/build_scripts/wazuh-agent.sh


COPY --from=builder /build/RPMS/*.rpm /tmp/rpms/
RUN dnf5 remove -y zfs-fuse && \
    ls /tmp/rpms/ && \
    dnf5 install -y /tmp/rpms/*.rpm && dnf clean all
# RUN find /tmp/rpms -name "*.rpm" -exec rpm -ivh {} \;

# RUN depmod -a

COPY rootfs/btrfs_config/ /
COPY rootfs/common/ /

RUN systemctl enable tailscaled

RUN bootc container lint
