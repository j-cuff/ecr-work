#!/bin/bash
# Deletes ECR repositories at or below the pack path configured in common-config.sh.
#
# Prerequisites:
#   - AWS CLI v2 configured with credentials that have ecr:DescribeRepositories + ecr:DeleteRepository
#   - aws configure --profile <your-govcloud-profile>  (or set AWS_PROFILE / AWS_ACCESS_KEY_ID etc.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-config.sh
source "${SCRIPT_DIR}/common-config.sh"

: "${AWS_ACCOUNT:?AWS_ACCOUNT must be set in common-config.sh}"
: "${AWS_REGION:?AWS_REGION must be set in common-config.sh}"
: "${ECR_REGISTRY:?ECR_REGISTRY must be set in common-config.sh}"
: "${ECR_BASE_CONTENT_PATH:?ECR_BASE_CONTENT_PATH must be set in common-config.sh}"

PACK_PATH="${ECR_BASE_CONTENT_PATH%/}"
if [[ -n "${ECR_PACK_BASE:-}" ]]; then
  PACK_PATH="${PACK_PATH}/${ECR_PACK_BASE#/}"
  PACK_PATH="${PACK_PATH%/}"
fi
PREFIX="${PACK_PATH}/spectro-packs"
DELETE_PATH="${ECR_REGISTRY}/${PREFIX}"

# Optional: set a named profile if needed
# export AWS_PROFILE="govcloud"

echo "Deletion scope:"
echo "  Account:           ${AWS_ACCOUNT}"
echo "  Region:            ${AWS_REGION}"
echo "  Repository prefix: ${PREFIX}"
echo "  Full ECR path:     ${DELETE_PATH}"
echo ""
echo "Only the repository '${PREFIX}' and repositories below '${PREFIX}/' are eligible."
echo ""
echo "==> Fetching repositories in the configured deletion scope..."

REPOS=$(aws ecr describe-repositories \
  --region "${AWS_REGION}" \
  --query "repositories[?repositoryName == '${PREFIX}' || starts_with(repositoryName, '${PREFIX}/')].repositoryName" \
  --output text)

if [[ -z "${REPOS}" ]]; then
  echo "No repositories found at or below '${DELETE_PATH}'. Nothing to delete."
  exit 0
fi

echo ""
echo "The following repositories will be DELETED:"
for REPO in ${REPOS}; do
  echo "  - ${ECR_REGISTRY}/${REPO}"
done

echo ""
echo "This permanently deletes every listed repository and all images in it."
read -rp "Type the exact deletion path to continue (${DELETE_PATH}): " CONFIRM
if [[ "${CONFIRM}" != "${DELETE_PATH}" ]]; then
  echo "Aborted: confirmation did not exactly match '${DELETE_PATH}'."
  exit 1
fi

echo ""
for REPO in ${REPOS}; do
  echo "==> Deleting repository: ${ECR_REGISTRY}/${REPO}"
  aws ecr delete-repository \
    --region "${AWS_REGION}" \
    --repository-name "${REPO}" \
    --force   # --force also deletes all images inside the repo
  echo "    Deleted: ${ECR_REGISTRY}/${REPO}"
done

echo ""
echo "Done. All repositories at or below '${DELETE_PATH}' have been deleted."
