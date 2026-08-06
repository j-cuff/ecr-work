#!/bin/bash
set -euo pipefail

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ecr-push-skip.XXXXXX")"
WRAPPER_DIR=""

cleanup() {
  if [[ -n "${WRAPPER_DIR}" && -d "${WRAPPER_DIR}" ]]; then
    rm -rf -- "${WRAPPER_DIR}"
  fi
  rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT

mkdir -p "${TEST_ROOT}/bin"

cat >"${TEST_ROOT}/bin/docker" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"${TEST_DOCKER_LOG}"

case "${TEST_DOCKER_RESULT:-success}" in
  success)
    ;;
  fail_twice)
    attempt_count="$(wc -l <"${TEST_DOCKER_LOG}" | tr -d ' ')"
    if ((attempt_count <= 2)); then
      echo "mock push failure ${attempt_count}" >&2
      exit 1
    fi
    ;;
  always_fail)
    echo "mock push failure" >&2
    exit 42
    ;;
  *)
    echo "Unexpected TEST_DOCKER_RESULT: ${TEST_DOCKER_RESULT}" >&2
    exit 99
    ;;
esac
EOF

cat >"${TEST_ROOT}/bin/aws" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"${TEST_AWS_LOG}"
case "${TEST_AWS_RESULT}" in
  exists)
    printf '%s\n' 'sha256:existing'
    ;;
  missing)
    echo 'An error occurred (ImageNotFoundException) when calling the DescribeImages operation: image does not exist' >&2
    exit 254
    ;;
  denied)
    echo 'An error occurred (AccessDeniedException) when calling the DescribeImages operation: access denied' >&2
    exit 254
    ;;
  *)
    echo "Unexpected TEST_AWS_RESULT: ${TEST_AWS_RESULT}" >&2
    exit 99
    ;;
esac
EOF

chmod +x "${TEST_ROOT}/bin/docker" "${TEST_ROOT}/bin/aws"

export TEST_DOCKER_LOG="${TEST_ROOT}/docker.log"
export TEST_AWS_LOG="${TEST_ROOT}/aws.log"
export PATH="${TEST_ROOT}/bin:/usr/bin:/bin"
export ECR_REGISTRY="123456789012.dkr.ecr.us-gov-west-1.amazonaws.com"
export AWS_REGION="us-gov-west-1"
export ECR_PUSH_RETRY_DELAY_SECONDS=0

# shellcheck source=../common-functions.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common-functions.sh"
enable_docker_push_skip_if_exists >/dev/null
WRAPPER_DIR="${PATH%%:*}"

test_fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local value="$1"
  local expected="$2"
  [[ "${value}" == *"${expected}"* ]] ||
    test_fail "expected output to contain '${expected}', got: ${value}"
}

run_docker() {
  set +e
  TEST_OUTPUT="$(docker "$@" 2>&1)"
  TEST_STATUS=$?
  set -e
}

: >"${TEST_DOCKER_LOG}"
: >"${TEST_AWS_LOG}"
export TEST_AWS_RESULT="exists"
run_docker push "${ECR_REGISTRY}/palette/spectro-images/api:v1"
[[ ${TEST_STATUS} -eq 0 ]] || test_fail "existing image check exited ${TEST_STATUS}"
assert_contains "${TEST_OUTPUT}" "Image already exists in ECR. Skipping push"
[[ ! -s "${TEST_DOCKER_LOG}" ]] || test_fail "existing image was pushed"
assert_contains "$(cat "${TEST_AWS_LOG}")" "--registry-id 123456789012"
assert_contains "$(cat "${TEST_AWS_LOG}")" "--repository-name palette/spectro-images/api"
assert_contains "$(cat "${TEST_AWS_LOG}")" "--image-ids imageTag=v1"

: >"${TEST_DOCKER_LOG}"
: >"${TEST_AWS_LOG}"
export TEST_AWS_RESULT="missing"
run_docker push "${ECR_REGISTRY}/palette/spectro-images/api:v2"
[[ ${TEST_STATUS} -eq 0 ]] || test_fail "missing image path exited ${TEST_STATUS}"
assert_contains "${TEST_OUTPUT}" "Image does not exist in ECR. Pushing"
assert_contains "$(cat "${TEST_DOCKER_LOG}")" "push ${ECR_REGISTRY}/palette/spectro-images/api:v2"

: >"${TEST_DOCKER_LOG}"
: >"${TEST_AWS_LOG}"
export TEST_AWS_RESULT="denied"
run_docker push "${ECR_REGISTRY}/palette/spectro-images/api:v3"
[[ ${TEST_STATUS} -eq 2 ]] || test_fail "failed lookup exited ${TEST_STATUS}, expected 2"
assert_contains "${TEST_OUTPUT}" "refusing to push"
assert_contains "${TEST_OUTPUT}" "AccessDeniedException"
[[ ! -s "${TEST_DOCKER_LOG}" ]] || test_fail "image was pushed after a failed lookup"

: >"${TEST_DOCKER_LOG}"
: >"${TEST_AWS_LOG}"
export TEST_AWS_RESULT="missing"
export TEST_DOCKER_RESULT="fail_twice"
run_docker push "${ECR_REGISTRY}/palette/spectro-images/api:v4"
[[ ${TEST_STATUS} -eq 0 ]] || test_fail "retried push exited ${TEST_STATUS}"
[[ "$(wc -l <"${TEST_DOCKER_LOG}" | tr -d ' ')" -eq 3 ]] ||
  test_fail "push did not make exactly three attempts"
assert_contains "${TEST_OUTPUT}" "Docker push failed (attempt 1/3)"
assert_contains "${TEST_OUTPUT}" "Docker push failed (attempt 2/3)"

: >"${TEST_DOCKER_LOG}"
: >"${TEST_AWS_LOG}"
export TEST_DOCKER_RESULT="always_fail"
run_docker push "${ECR_REGISTRY}/palette/spectro-images/api:v5"
[[ ${TEST_STATUS} -eq 42 ]] || test_fail "exhausted push exited ${TEST_STATUS}, expected 42"
[[ "$(wc -l <"${TEST_DOCKER_LOG}" | tr -d ' ')" -eq 3 ]] ||
  test_fail "failed push did not stop after exactly three attempts"
assert_contains "${TEST_OUTPUT}" "Docker push failed after 3 attempts"

echo "PASS: ECR push existence checks and retries"
