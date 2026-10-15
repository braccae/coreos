if [ "$(id -u)" -ne 0 ]; then
  export CONTAINER_HOST="unix:///run/podman/podman.sock"
  export DOCKER_HOST="unix:///var/run/docker.sock"
fi
