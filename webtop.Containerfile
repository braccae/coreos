FROM ghcr.io/braccae/ublue:latest



ADD https://github.com/kasmtech/KasmVNC/releases/download/v1.3.4/kasmvncserver_fedora_fortyone_1.3.4_x86_64.rpm /tmp/kasmvnc.rpm

RUN dnf5 install -y /tmp/kasmvnc.rpm

COPY rootfs/common/ /
COPY rootfs/webtop/ /

RUN useradd -m -u 1000 -G wheel,kasmvnc-cert webtop && \
    usermod -U webtop && \
    passwd -d webtop

ENTRYPOINT [ "/sbin/init" ]