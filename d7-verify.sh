#!/bin/bash
# D7 acceptance verification. Run from the d7-hermes worktree.
IMG=localhost/alma:d7-hermes
{
  echo "################ D7 EVIDENCE ################"
  echo "date: $(date -Is)"
  echo "host: $(uname -srm)"
  echo "image: $IMG"
  podman image inspect "$IMG" --format 'image id: {{.Id}}' 2>/dev/null
  echo

  echo "########## [1] build ##########"
  echo "see d7-build.log ; BUILD_EXIT=$(tail -1 d7-build.log | sed 's/BUILD_EXIT=//')"
  echo "hermes install step executed (not cached):"
  grep -n "STEP .*install-hermes" d7-build.log
  echo

  echo "########## [2a] hermes --version (literal spec form) ##########"
  echo "\$ podman run --rm $IMG hermes --version"
  podman run --rm "$IMG" hermes --version 2>&1
  echo "RC=$?"
  echo

  echo "########## [2b] hermes --version (entrypoint cleared) ##########"
  echo "\$ podman run --rm --entrypoint '' $IMG hermes --version"
  podman run --rm --entrypoint "" "$IMG" hermes --version 2>&1
  echo "RC=$?"
  echo

  echo "########## [2c] hermes --version as uid 1000 ##########"
  echo "\$ podman run --rm --entrypoint '' --user 1000 $IMG hermes --version"
  podman run --rm --entrypoint "" --user 1000 "$IMG" hermes --version 2>&1
  echo "RC=$?"
  echo

  echo "########## [2d] proof the system-wide symlink resolves ##########"
  echo "\$ podman run --rm --entrypoint '' $IMG ls -l /usr/local/bin/hermes"
  podman run --rm --entrypoint "" "$IMG" ls -l /usr/local/bin/hermes 2>&1
  echo

  echo "########## [2e] HERMES_HOME baked in image env ##########"
  echo "\$ podman image inspect $IMG --format '{{.Config.Env}}' | tr ' ' '\n' | grep HERMES"
  podman image inspect "$IMG" --format '{{.Config.Env}}' 2>/dev/null | tr ' ' '\n' | grep HERMES
  echo

  echo "########## [3] bootc container lint ##########"
  echo "\$ podman run --rm --entrypoint '' $IMG bootc container lint"
  podman run --rm --entrypoint "" "$IMG" bootc container lint 2>&1 | tail -25
  echo "RC=${PIPESTATUS[0]}"
  echo

  echo "########## [4] just hermes alma d7-hermes --version ##########"
  echo "\$ just hermes alma d7-hermes --version"
  just hermes alma d7-hermes --version 2>&1
  echo "RC=$?"
  echo

  echo "################ END D7 EVIDENCE ################"
} 2>&1 | tee d7-evidence.log
