FROM quay.io/fedora/fedora-bootc:42 AS zfs-builder

ARG ZFS_VERSION="2.3.4"

COPY scripts/build/zfs.sh /tmp/build_scripts/zfs.sh
RUN bash /tmp/build_scripts/zfs.sh


FROM scratch

COPY --from=zfs-builder /build/RPMS/ /zfs