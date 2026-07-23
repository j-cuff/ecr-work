#!/bin/bash
# Deletes all ECR repositories under 103448924380.dkr.ecr.us-gov-west-1.amazonaws.com/cuff-airgap
#
# Prerequisites:
#   - AWS CLI v2 configured with credentials that have ecr:DescribeRepositories + ecr:DeleteRepository
#   - aws configure --profile <your-govcloud-profile>  (or set AWS_PROFILE / AWS_ACCESS_KEY_ID etc.)

set -euo pipefail

ACCOUNT_ID="103448924380"
REGION="us-gov-west-1"
PREFIX="cuff-airgap/spectro-packs"

# Optional: set a named profile if needed
# export AWS_PROFILE="govcloud"

echo "==> Fetching all ECR repositories with prefix '${PREFIX}' in ${REGION}..."

REPOS=$(aws ecr describe-repositories \
  --region "${REGION}" \
  --query "repositories[?starts_with(repositoryName, '${PREFIX}')].repositoryName" \
  --output text)

if [[ -z "${REPOS}" ]]; then
  echo "No repositories found matching prefix '${PREFIX}'. Nothing to delete."
  exit 0
fi

echo ""
echo "The following repositories will be DELETED:"
for REPO in ${REPOS}; do
  echo "  - ${REPO}"
done

echo ""
read -rp "Are you sure you want to delete all of the above? (yes/no): " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

echo ""
# The only confirmation occurs above. Delete each listed repository without
# opening the AWS CLI response pager or requesting additional input.
for REPO in ${REPOS}; do
  echo "==> Deleting repository: ${REPO}"
  aws --no-cli-pager ecr delete-repository \
    --region "${REGION}" \
    --repository-name "${REPO}" \
    --force \
    >/dev/null   # --force also deletes all images inside the repo
  echo "    Deleted: ${REPO}"
done

echo ""
echo "Done. All matching repositories have been deleted."
