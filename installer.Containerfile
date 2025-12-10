ARG installer_base=ghcr.io/braccae/coreos:workstation
FROM $installer_base

RUN dnf install -y \
     anaconda \
     anaconda-install-env-deps \
     anaconda-dracut \
     dracut-config-generic \
     dracut-network \
     net-tools \
     squashfs-tools \
     grub2-efi-x64-cdboot \
     python3-mako \
     lorax-templates-* \
     biosdevname \
     prefixdevname \
     && dnf clean all
# shim-x64 is marked installed but the files are not in the expected
# place for https://github.com/osbuild/osbuild/blob/v160/stages/org.osbuild.grub2.iso#L91, see
# workaround via reinstall, we could add a config to the grub2.iso
# stage to allow a different prefix that then would be used by
# anaconda.
# once https://github.com/osbuild/osbuild/pull/2202 is merged we
# can update images/ to set the correct efi_src_dir and this can
# be removed
RUN dnf reinstall -y shim-x64
# lorax wants to create a symlink in /mnt which points to /var/mnt
# on bootc but /var/mnt does not exist on some images.
#
# If https://gitlab.com/fedora/bootc/base-images/-/merge_requests/294
# gets merged this will be no longer needed
RUN mkdir /var/mnt