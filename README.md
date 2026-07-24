# Palette airgap content in Amazon ECR

This directory contains scripts for uploading Palette Vertex airgap images and
packs to Amazon ECR, uploading individual `.zst` bundles, and deleting pack
repositories.

Run the scripts from this directory because most of them source
`./common-config.sh` and `./common-functions.sh` using relative paths:

```bash
cd /path/to/ecr
```

## Scripts

| Script | Use case |
| --- | --- |
| `push_to_ecr.sh` | Extract a Palette Vertex airgap binary and push all included images, packs, and manifests to ECR. |
| `push_zst_to_ecr.sh` | Push `.zst` bundles that already exist in a local directory. |
| `push_from_url.sh` | Download bundles and signatures listed in `zst_urls.txt`, verify signatures, and push the `.zst` files. |
| `delete_ecr_images.sh` | Delete the configured pack repository tree after an exact-path confirmation. This is the recommended deletion script. |
| `common-config.sh` | Shared version, registry, path, and download configuration. |
| `common-functions.sh` | Shared validation, authentication, extraction, patching, retry, and prerequisite functions. |
| `zst_urls.txt` | URL input consumed by `push_from_url.sh`. |

## Security and safety

- Do not commit real download passwords or AWS credentials.
- Prefer an AWS profile, IAM role, or standard AWS environment variables over
  access keys stored in these scripts.
- `DOWNLOAD_USER` and `DOWNLOAD_PASS` are masked by `push_to_ecr.sh`. The current
  `push_from_url.sh` validation prints both values, so do not share or publish
  its terminal output.
- `delete_ecr_images.sh` uses `aws ecr delete-repository --force`. This
  permanently deletes each selected repository and all images in it.
- Review every resolved registry path before approving a push or deletion.
- `push_zst_to_ecr.sh` and `push_from_url.sh` pass `--insecure` to
  `palette content push`. Confirm that this is appropriate for the target
  registry.

## Shared configuration

Edit `common-config.sh` before running the scripts.

| Variable | Purpose | Example |
| --- | --- | --- |
| `VERTEX_VERSION` | Palette Vertex airgap version. | `4.9.18` |
| `AWS_ACCOUNT` | AWS account ID that owns the ECR registry. | `<account-id>` |
| `AWS_REGION` | ECR region. | `us-gov-west-1` |
| `ECR_REGISTRY` | Registry hostname derived from account and region. | `<account-id>.dkr.ecr.<region>.amazonaws.com` |
| `ECR_BASE_CONTENT_PATH` | Root repository namespace. | `palette-airgap` |
| `ECR_IMAGE_BASE` | Image namespace below the base content path. | `spectro-images` |
| `ECR_PACK_BASE` | Optional pack namespace appended below `ECR_BASE_CONTENT_PATH`. | Empty for the full airgap push; `spectro-packs` for `push_zst_to_ecr.sh` |
| `ECR_DELETE_PATH` | Exact repository prefix that `delete_ecr_images.sh` may delete, relative to `ECR_REGISTRY`. A leading or trailing slash is normalized away. | `/palette-airgap/spectro-packs` |
| `DOWNLOAD_USER` | Optional for `push_to_ecr.sh`; required by `push_from_url.sh`. | Set locally |
| `DOWNLOAD_PASS` | Optional for `push_to_ecr.sh`; required by `push_from_url.sh`. | Set locally |
| `SCRIPT_DIR` | Absolute directory containing the scripts, derived automatically. | Do not normally override |
| `AIRGAP_DIR` | Extraction directory for the airgap binary. | `spectroairgap-4.9.18` |
| `SKIP_EXTRACTION` | Reuse an existing extraction directory when `true`. | `false` |
| `BINARY` | Airgap installer filename. | `airgap-vertex-v4.9.18.bin` |
| `PUBLIC_KEY` | Public key filename used to verify bundle signatures. | `spectro_public_key.pem` |
| `PUBLIC_KEY_URL` | Download URL for the public verification key. | Artifact Studio public-key URL |

The full-push workflow resolves the default destinations as:

```text
Images: <registry>/<base-content-path>/spectro-images/...
Packs:  <registry>/<base-content-path>/spectro-packs/archive/...
```

The scripts do not use `ECR_PACK_BASE` identically:

- `push_to_ecr.sh` appends it below `ECR_BASE_CONTENT_PATH`, and the extracted
  airgap setup adds its own `spectro-packs` repository structure. Keep
  `ECR_PACK_BASE` empty for the default
  `<base-content-path>/spectro-packs/...` layout.
- `push_zst_to_ecr.sh` pushes directly to
  `<ECR_BASE_CONTENT_PATH>/<ECR_PACK_BASE>`.
- `push_from_url.sh` overrides `ECR_PACK_BASE` with `spectro-packs` regardless
  of the value in `common-config.sh`.

## Prerequisites

The scripts have different requirements:

| Script | Requirements enforced or used |
| --- | --- |
| `push_to_ecr.sh` | AWS CLI v2, ORAS, Docker CLI with a running daemon, `zip`, `unzip`, and `jq`. It also uses `curl` if the airgap binary must be downloaded. |
| `push_zst_to_ecr.sh` | A supported Palette CLI, AWS CLI, and a directory containing `.zst` files. The script explicitly rejects macOS. |
| `push_from_url.sh` | A supported Palette CLI, AWS CLI, `curl`, OpenSSL, `zst_urls.txt`, and download credentials. |
| `delete_ecr_images.sh` | AWS CLI configured for the target account and region. |

Only `push_to_ecr.sh` runs the shared prerequisite checker. It detects macOS,
Linux, WSL, and Windows and prints platform-specific installation instructions
for missing tools. AWS CLI v1 is rejected. ORAS must be installed, but an
installed version other than v1.0.0 produces a warning and execution continues.

The individual bundle scripts do not run that shared checker. Install and
configure their dependencies before execution. The Palette CLI used by these
workflows is not available as a compatible multi-architecture macOS binary;
use a supported Linux environment. `push_zst_to_ecr.sh` enforces this
restriction, while `push_from_url.sh` currently does not contain the same
precheck.

The AWS identity needs permissions appropriate to the selected workflow,
which can include:

- ECR authentication and image upload permissions
- `ecr:DescribeRepositories`
- `ecr:CreateRepository` when automatic repository creation is needed
- `ecr:DescribeImages`
- `ecr:DeleteRepository` for deletion workflows

Verify AWS access before running:

```bash
aws sts get-caller-identity
aws ecr describe-repositories --region "<region>" --max-results 5
```

## Use case 1: Push a complete Vertex airgap binary

Configure `common-config.sh`, then run:

```bash
./push_to_ecr.sh
```

The script also accepts the documented version argument:

```bash
./push_to_ecr.sh 4.9.18
```

Current behavior still uses `VERTEX_VERSION` from `common-config.sh` as the
effective version, so keep that value synchronized with any positional version
argument. The workflow also reconstructs `BINARY` as
`./airgap-vertex-v<VERTEX_VERSION>.bin`; changing only `BINARY` in
`common-config.sh` does not select a different filename.

The workflow:

1. Creates `push_to_ecr-<version>-<timestamp>.log`.
2. Detects the operating system.
3. Validates shared configuration, masking download credentials.
4. Checks prerequisites and required tool versions.
5. Authenticates ORAS and Docker to ECR.
6. Enables a Docker wrapper that skips image tags already present in ECR.
7. Locates the airgap binary or offers to download it.
8. Extracts the binary into `AIRGAP_DIR`.
9. Replaces `ecr-public` with `ecr` in the extracted functions on macOS and
   Linux, and patches push messages to show full destination paths.
10. Displays the exact image and pack roots.
11. Requires confirmation before any pack or image push.
12. Runs `apply_pack.sh` and `apply_patch.sh`.
13. Detects missing pack archive repositories, creates them, and retries that
    setup script, up to 20 attempts.
14. Removes the extraction directory after a successful normal run.

If `apply_pack.sh` or `apply_patch.sh` is absent from the extracted directory,
the helper warns and skips that script.

If the binary is missing, the script prompts before downloading it. For an
unattended approved download:

```bash
DOWNLOAD_BINARY=true ./push_to_ecr.sh
```

Each pushed pack is displayed with its full destination:

```text
- Pushing Pack to <registry>/<base>/spectro-packs/archive/cni-calico:3.31.4
```

Image operations display both resolved destination references created by the
airgap setup script.

### Existing extraction directory

Without `--skip-extraction`, an existing `AIRGAP_DIR` causes the run to stop
rather than overwrite it.

Use the next workflow to reuse that directory.

## Use case 2: Reuse an extracted airgap directory

Use this when `AIRGAP_DIR` already contains a complete extraction:

```bash
./push_to_ecr.sh --skip-extraction
```

The short form is:

```bash
./push_to_ecr.sh -s
```

With this option:

- The script does not check for or download the airgap binary.
- The existing `AIRGAP_DIR` must be present.
- The extracted functions are patched again safely; the path-output patch is
  idempotent.
- The extraction directory is preserved after the run.

If a fresh run is cancelled at the destination confirmation, its already
extracted directory remains available and can be reused with
`--skip-extraction`.

## Use case 3: Push local `.zst` bundles

Place one or more `.zst` files in a directory and run:

```bash
./push_zst_to_ecr.sh ./bundles
```

This workflow is not supported on macOS because the required Palette CLI is
not available as a compatible multi-architecture binary. The script detects
macOS and exits before validation, authentication, or bundle processing. Run it
from a supported Linux environment instead.

The script:

1. Loads shared ECR configuration and rejects macOS.
2. Logs the Palette CLI into ECR using an AWS ECR authorization token.
3. Pushes every `./bundles/*.zst` file with `palette content push`.
4. Stops if the directory contains no `.zst` files.

The destination joins the nonempty configured path components:

```text
<ECR_REGISTRY>/<ECR_BASE_CONTENT_PATH>/<ECR_PACK_BASE>
```

Set `ECR_PACK_BASE="spectro-packs"` in `common-config.sh` when the intended
destination is the standard pack root. There is no destination confirmation in
this script; review the configuration before running it.

## Use case 4: Download, verify, and push bundles from URLs

Add one URL per line to `zst_urls.txt` in the current working directory. Empty
lines and lines beginning with `#` are ignored. Include both each `.zst` URL
and its matching `.sig.bin` URL. The script does not accept an alternate URL
file argument.

Run:

```bash
./push_from_url.sh ./bundles
```

The script:

1. Requires nonempty `DOWNLOAD_USER` and `DOWNLOAD_PASS`.
2. Downloads every listed URL into `./bundles/downloads` using HTTP basic
   authentication.
3. Skips files already present locally without downloading or revalidating
   them.
4. Downloads the configured public key if necessary.
5. For each `.zst`, looks for a sibling signature named
   `<bundle-name>.sig.bin`.
6. Verifies available pairs and displays passed and failed signature counts.
7. Authenticates the Palette CLI to ECR.
8. Pushes all downloaded `.zst` files with `--insecure`.

This workflow sets `ECR_PACK_BASE="spectro-packs"` internally. Its destination
is:

```text
<ECR_REGISTRY>/<ECR_BASE_CONTENT_PATH>/spectro-packs
```

Important limitations in the current implementation:

- A failed signature increments the failure count, but does not stop the push.
- A missing bundle or signature is reported as `SKIP` and is not included in
  the failure count.
- The download loop does not use `curl --fail`, and the script does not use
  `set -e`, so a failed download might not stop the workflow.
- The script does not ask for destination confirmation.

Review download and verification output before allowing the push to continue.

## Use case 5: Delete the configured pack repository tree

`delete_ecr_images.sh` is the safer, configuration-driven deletion workflow:

```bash
./delete_ecr_images.sh
```

It:

1. Sources `common-config.sh`.
2. Reads `ECR_DELETE_PATH` as the only configured repository prefix eligible
   for deletion. The value is relative to `ECR_REGISTRY`, for example:

   ```text
   ECR_DELETE_PATH="/palette-airgap/spectro-packs"
   ```

   Do not include the registry hostname. A leading or trailing slash is
   removed.

3. Validates that the normalized value is a valid lowercase ECR repository
   prefix.
4. Resolves the full confirmation path as
   `<ECR_REGISTRY>/<normalized-ECR_DELETE_PATH>`.
5. Selects only the exact configured repository and repositories below it.
6. Exits successfully without prompting when no repositories match.
7. Displays every full ECR repository path selected for deletion.
8. Requires the operator to type the complete resolved deletion path.
9. Force-deletes every listed repository and all contained images.

Any confirmation mismatch aborts before deletion.

## Logs and generated files

`push_to_ecr.sh` writes:

```text
push_to_ecr-<vertex-version>-<YYYYmmddHHMMSS>.log
```

The full console stream is copied to this file. The `.gitignore` excludes:

- `push_to_ecr-*.log`
- extracted `spectroairgap-*` directories
- the currently listed `airgap-vertex-v4.9.18.bin`
- the explicitly listed bundle and signature filenames

The binary and bundle ignore entries are not general wildcard rules. If the
configured version or bundle names change, update `.gitignore` before running
or committing.

The retry helper creates temporary attempt logs under `/tmp`. Successful
attempt logs are removed. Relevant failed output is replayed into the main log.

Downloaded URL bundles are stored beneath:

```text
<bundle-dir>/downloads/
```

That generated directory is not ignored by a general `.gitignore` rule. Use a
disposable bundle directory or add an appropriate repository-specific ignore
entry before downloading sensitive or large artifacts.

## Troubleshooting

### Prerequisite check fails

This check is run only by `push_to_ecr.sh`. Follow its OS-specific guidance and
confirm versions with:

```bash
aws --version
oras version
docker version
docker info
zip -v
unzip -v
jq --version
```

AWS output must begin with `aws-cli/2.`. ORAS v1.0.0 is recommended; a
different or unrecognized ORAS version produces a warning but does not stop
execution.

### Palette CLI workflow fails on macOS

Run the bundle workflow from a supported Linux environment.
`push_zst_to_ecr.sh` rejects macOS immediately. `push_from_url.sh` currently
does not perform the precheck, but it still invokes the same Palette CLI.

### Docker is installed but unavailable

Start the daemon before rerunning:

- macOS: start Docker Desktop, or run `open -a Docker`.
- Linux: start the configured Docker service, commonly
  `sudo systemctl start docker`.
- WSL: start Docker Desktop and enable WSL integration.

### Airgap directory already exists

Either reuse it:

```bash
./push_to_ecr.sh --skip-extraction
```

or move it aside after verifying that it is safe to do so. The script does not
overwrite an existing extraction.

### Airgap directory is missing with `--skip-extraction`

Run without `--skip-extraction` to extract the configured binary, or correct
`AIRGAP_DIR`.

### Missing ECR repository

The full-push workflow attempts to detect missing pack repositories, creates
them, and retries. Confirm the AWS identity has `ecr:CreateRepository`.

### Existing image tags

The Docker wrapper checks ECR before pushing. Existing tags are skipped and the
full image reference is printed.

### Authentication failure

Verify:

```bash
aws sts get-caller-identity
aws ecr get-login-password --region "<region>"
```

Confirm the configured account, region, registry hostname, IAM permissions, and
active AWS profile.

### Incorrect destination

For `push_to_ecr.sh`, do not approve the confirmation. Correct
`ECR_BASE_CONTENT_PATH`, `ECR_IMAGE_BASE`, or `ECR_PACK_BASE`, then rerun and
review the resolved paths.

The two bundle push scripts do not prompt. Stop them before the push and correct
the shared configuration. For deletion, correct `ECR_DELETE_PATH` and rerun;
never confirm an unexpected full path.
