#!/bin/bash
# quick_push_zsts.sh
# Prerequisites: palette CLI installed and configured, AWS CLI installed and configured, ORAS installed and configured, common-config.sh 
# Usage: ./quick_push_zsts.sh <bundle-dir>
# Example: ./quick_push_zsts.sh ./bundles
# Used to push all .zst bundles from a directory to ECR using the palette content push command.

set -euo pipefail
source ./common-config.sh
source ./common-functions.sh

os_type="$(detect_os)"
if [[ "${os_type}" == "macos" ]]; then
  echo "ERROR: push_zst_to_ecr.sh is not supported on macOS because the Palette CLI is not available as a compatible multi-architecture binary." >&2
  echo "Run this script from a supported Linux environment instead." >&2
  exit 1
fi

validateVar AWS_ACCOUNT
validateVar AWS_REGION
validateVar ECR_BASE_CONTENT_PATH warn || true
validateVar ECR_IMAGE_BASE warn || true
validateVar ECR_PACK_BASE warn || true
validateVar ECR_REGISTRY

BUNDLE_DIR="${1:?Usage: $0 <bundle-dir>}" || echo "Bundle Directory: ${BUNDLE_DIR}"
BASE_PATH="${ECR_BASE_CONTENT_PATH:+${ECR_BASE_CONTENT_PATH%/}/}${ECR_PACK_BASE#/}" || echo "Base Content Path: ${BASE_PATH}"

echo "==> Authenticating to ECR..."

palette content registry-login \
  --registry ${ECR_REGISTRY} \
  --username AWS \
  --password "$(aws ecr get-login-password \
  --region ${AWS_REGION})"

echo "==> Pushing all .zst bundles from ${BUNDLE_DIR} to ${ECR_REGISTRY}/${BASE_PATH}"

for bundle in "${BUNDLE_DIR}"/*.zst; do
  [[ -f "$bundle" ]] || { echo "No .zst files found in ${BUNDLE_DIR}"; exit 1; }
  echo "--> Pushing: ${bundle}"
  palette content push \
    --file "${bundle}" \
    --registry "${ECR_REGISTRY}/${BASE_PATH}" \
    --insecure
done

echo "==> All bundles pushed successfully."
