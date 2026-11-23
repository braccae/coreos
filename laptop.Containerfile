FROM ghcr.io/ublue-os/bazzite-dx-gnome:stable-44

COPY repos/ /etc/yum.repos.d/
RUN rm -rv /etc/yum.repos.d/wazuh.repo /etc/yum.repos.d/crowdsec.repo
COPY rootfs/workstation/ /
COPY build/justfile /tmp/

WORKDIR /tmp

RUN mkdir -p /var/lib/alternatives && \
    just install-ublue-repos

RUN just install-ansible && \
    just install-java && \
    just install-misc-tools && \
    just install-dev-mode && \
    just install-cloudflare-warp

RUN ostree container commit
ENTRYPOINT [ "/sbin/init" ]