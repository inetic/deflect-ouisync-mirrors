#!/bin/bash

set -e

dockerfile_flag="-f aux/Dockerfile"

docker build $dockerfile_flag . --tag deflect-ouisync-451

# Flags needed for Fuse mounting
# https://stackoverflow.com/a/49021109/273348
fuse_mounting_flags="--device /dev/fuse --cap-add SYS_ADMIN --security-opt apparmor:unconfined"

docker run \
    --rm \
    -it \
    --net=host \
    $fuse_mounting_flags \
    deflect-ouisync-451 \
    bash
