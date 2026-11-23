ARG BASE_IMAGE=quay.io/almalinuxorg/almalinux-bootc:10
FROM ${BASE_IMAGE} AS kmods-builder

ARG ZFS_VERSION="zfs-2.4.4"

# Copy persistent MOK public key for secure boot
COPY keys/mok/LOCALMOK.der /etc/pki/mok/LOCALMOK.der

RUN --mount=type=bind,source=build/scripts/build-zfs.sh,target=/tmp/build-zfs.sh \
    --mount=type=secret,mode=0600,id=LOCALMOK \
    bash /tmp/build-zfs.sh && \
    for d in /usr/lib/modules/*/; do \
        if [ -f "${d}vmlinuz" ]; then \
            basename "$d" > /tmp/zfs-rpms/kernel-version.txt; \
            break; \
        fi; \
    done && \
    test -s /tmp/zfs-rpms/kernel-version.txt

FROM scratch
COPY --from=kmods-builder /tmp/zfs-rpms/ /zfs/