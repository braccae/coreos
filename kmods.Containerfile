ARG BASE_IMAGE=quay.io/almalinuxorg/almalinux-bootc:10
FROM ${BASE_IMAGE} AS zfs-builder

ARG ZFS_VERSION="zfs-2.4.2"

# Copy persistent MOK public key for secure boot
COPY keys/mok/LOCALMOK.der /etc/pki/mok/LOCALMOK.der

COPY build/scripts/build-zfs.sh /tmp/build_scripts/zfs.sh
RUN --mount=type=secret,mode=0600,id=LOCALMOK \
    bash /tmp/build_scripts/zfs.sh && \
    BOOTC_KERNEL_VERSION=$(find /usr/lib/modules/ -maxdepth 1 -type d ! -path "/usr/lib/modules/" -printf "%f\n" | head -1) && \
    echo "$BOOTC_KERNEL_VERSION" > /tmp/zfs-rpms/kernel-version.txt

FROM scratch
COPY --from=zfs-builder /tmp/zfs-rpms/ /zfs/