#!/bin/bash
#
# Build and push the workshop tools image (x86_64 only; the workshop does not support ARM).

# Fail if QUAY_USER is not set or empty
if [[ -z "${QUAY_USER}" ]]; then
  echo "Error: QUAY_USER is not set."
  echo "Please export QUAY_USER before running this script, e.g.:"
  echo "  export QUAY_USER=your-quay-username"
  exit 1
fi

set -e

cd "$(dirname "$0")"

IMAGE="quay.io/$QUAY_USER/workshop-tools:latest"

podman build --platform linux/amd64 --pull=newer -t "$IMAGE" -f Containerfile .
podman push "$IMAGE"

echo ""
echo "=============================================="
echo "Build and push successful!"
echo "Image pushed to: $IMAGE"
echo ""
echo "You can try the container using:"
echo "  podman run --rm -it --platform linux/amd64 $IMAGE bash"
echo "=============================================="
