#!/bin/bash
# download and push bundles
# Usage: ./push_from_url.sh <zst-urls-file>
# Example: ./push_from_url.sh ./zst_urls.txt
# Build a bundle, copy urls to file, then download and push to ECR using this script.
set -euo pipefail
source ./common-config.sh
source ./common-functions.sh

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <zst-urls-file>" >&2
  exit 2
fi

BUNDLE_URL_FILE="$1"
if [[ ! -f "${BUNDLE_URL_FILE}" ]]; then
  echo "Error: URL file '${BUNDLE_URL_FILE}' not found." >&2
  exit 1
fi

BUNDLE_URL_DIR="$(cd "$(dirname "${BUNDLE_URL_FILE}")" && pwd)"
BUNDLE_URL_FILE="${BUNDLE_URL_DIR}/$(basename "${BUNDLE_URL_FILE}")"
BUNDLE_DIR="${BUNDLE_URL_DIR}"
DOWNLOAD_DIR="${BUNDLE_DIR}/downloads"
mkdir -p "${DOWNLOAD_DIR}"

ECR_PACK_BASE="spectro-packs"
validateVar AWS_ACCOUNT
validateVar AWS_REGION
validateVar ECR_BASE_CONTENT_PATH warn || true
validateVar ECR_IMAGE_BASE warn || true
validateVar ECR_PACK_BASE warn || true
validateVar ECR_REGISTRY
validateVar DOWNLOAD_USER fatal mask
validateVar DOWNLOAD_PASS fatal mask

export BUNDLE_DIR
export BUNDLE_URL_FILE
export BASE_PATH="${ECR_BASE_CONTENT_PATH:+${ECR_BASE_CONTENT_PATH%/}/}${ECR_PACK_BASE#/}"


echo "==> Downloading all .zst bundles from ${BUNDLE_URL_FILE} to ${DOWNLOAD_DIR}"

echo "Reading URLs from: $BUNDLE_URL_FILE"
echo ""

while IFS= read -r url; do
  # Skip empty lines and lines starting with #
  [[ -z "$url" || "$url" == \#* ]] && continue

  filename="${url##*/}"
  dest="${DOWNLOAD_DIR}/${filename}"

  # ── Skip if file already exists ──────────────────────────────────────────────
  if [[ -f "$dest" ]]; then
    echo "SKIP  $filename (already exists in ${DOWNLOAD_DIR})"
    echo ""
    continue
  fi

  echo "Downloading: $filename"
  echo "  From: $url"
  echo "  To:   $dest"
  curl -L -u "${DOWNLOAD_USER}:${DOWNLOAD_PASS}" -o "$dest" "$url"
  echo ""
done < "$BUNDLE_URL_FILE"

echo "All downloads complete!"

echo "Validating downloaded files in ${DOWNLOAD_DIR}..."
PUBLIC_KEY_PATH="${DOWNLOAD_DIR}/${PUBLIC_KEY}"
if [[ ! -f "${PUBLIC_KEY_PATH}" ]]; then
  echo "Public key not found. Downloading..."
  curl -fL "$PUBLIC_KEY_URL" -o "${PUBLIC_KEY_PATH}"

  if [[ ! -f "${PUBLIC_KEY_PATH}" ]]; then
    echo "Error: Failed to download '${PUBLIC_KEY}'. Cannot verify signatures."
    exit 1
  fi

  chmod 644 "${PUBLIC_KEY_PATH}"

  echo "Public key saved: ${PUBLIC_KEY_PATH}"
else
  echo "Public key already exists: ${PUBLIC_KEY_PATH}"
fi

echo ""

echo "Verifying signatures..."
echo ""

passed=0
failed=0

while IFS= read -r url; do
  [[ -z "$url" || "$url" == \#* ]] && continue

  filename="${url##*/}"

  # Only process .zst files; find the matching .sig.bin
  if [[ "$filename" == *.zst ]]; then
    sigfile="${filename%.zst}.sig.bin"

    zst_path="${DOWNLOAD_DIR}/${filename}"
    sig_path="${DOWNLOAD_DIR}/${sigfile}"
    key_path="${DOWNLOAD_DIR}/${PUBLIC_KEY}"

    if [[ ! -f "$zst_path" ]]; then
      echo "SKIP  $filename (file not found: $zst_path)"
      continue
    fi

    if [[ ! -f "$sig_path" ]]; then
      echo "SKIP  $filename (signature not found: $sig_path)"
      continue
    fi

    result=$(
      openssl dgst -sha256 \
        -verify "$key_path" \
        -signature "$sig_path" \
        "$zst_path" 2>&1
    )

    if [[ "$result" == "Verified OK" ]]; then
      echo "OK    $filename"
      passed=$((passed + 1))
    else
      echo "FAIL  $filename ($result)"
      failed=$((failed + 1))
    fi
  fi
done < "$BUNDLE_URL_FILE"

echo ""
echo "Results: $passed passed, $failed failed"
echo "==> Authenticating to ECR..."

palette content registry-login \
  --registry ${ECR_REGISTRY} \
  --username AWS \
  --password "$(aws ecr get-login-password \
  --region ${AWS_REGION})"

echo "==> Pushing all .zst bundles from ${DOWNLOAD_DIR} to ${ECR_REGISTRY}/${BASE_PATH}"

for bundle in "${DOWNLOAD_DIR}"/*.zst; do
  [[ -f "$bundle" ]] || { echo "No .zst files found in ${DOWNLOAD_DIR}"; exit 1; }
  echo "--> Pushing: ${bundle}"
  palette content push \
    --file "${bundle}" \
    --registry "${ECR_REGISTRY}/${BASE_PATH}" \
    --insecure
done

echo "==> All bundles pushed successfully."
unset BUNDLE_DIR
unset BUNDLE_URL_FILE
unset DOWNLOAD_DIR
unset BASE_PATH
