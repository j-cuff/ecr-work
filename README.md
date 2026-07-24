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
| `delete_ecr_images-2.sh` | Delete repositories under a hard-coded prefix after one `yes` confirmation. |
| `common-config.sh` | Shared version, registry, path, and download configuration. |
| `common-functions.sh` | Shared validation, authentication, extraction, patching, retry, and prerequisite functions. |

## Security and safety

- Do not commit real download passwords or AWS credentials.
- Prefer an AWS profile, IAM role, or standard AWS environment variables over
  access keys stored in these scripts.
- `DOWNLOAD_USER` and `DOWNLOAD_PASS` are masked in `push_to_ecr.sh` validation
  output, but their values remain available internally for authenticated
  downloads.
- The deletion scripts use `aws ecr delete-repository --force`. This permanently
  deletes each selected repository and all images in it.
- Review every resolved registry path before approving a push or deletion.
- The bundle push scripts currently pass `--insecure` to `palette content push`.
  Confirm that this is appropriate for the target registry.

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
| `ECR_PACK_BASE` | Optional pack namespace below the base content path. | Empty, or `spectro-packs` for direct bundle pushes |
| `ECR_DELETE_PATH` | Exact repository prefix that `delete_ecr_images.sh` may delete, relative to `ECR_REGISTRY`. | `palette-airgap/spectro-packs` |
| `DOWNLOAD_USER` | Optional username for downloading the airgap binary and bundles. | Set locally |
| `DOWNLOAD_PASS` | Optional password for authenticated downloads. | Set locally |
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

## Prerequisites

`push_to_ecr.sh` validates these requirements before authenticating:

| Requirement | Why it is needed |
| --- | --- |
| AWS CLI v2 | Interacts with Amazon ECR. AWS CLI v1 is rejected. |
| ORAS CLI (v1.0.0 recommended) | Required by the extracted airgap setup scripts. Other ORAS versions produce a warning but do not stop execution. |
| Docker CLI and running daemon | Loads, tags, and pushes images from the airgap bundle. |
| `zip` | Used by the airgap setup scripts. |
| `unzip` | Extracts manifest content from the airgap binary. |
| `jq` | Processes JSON used by the setup scripts. |

The checker detects macOS, Linux, WSL, and Windows and prints platform-specific
installation instructions for missing or incorrect tools.

Additional tools are needed for the individual bundle workflows:

- Palette CLI, installed and configured
- `curl`
- OpenSSL for signature verification in `push_from_url.sh`

The AWS identity needs permissions appropriate to the selected workflow,
including:

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
argument.

The workflow:

1. Creates `push_to_ecr-<version>-<timestamp>.log`.
2. Detects the operating system.
3. Validates shared configuration, masking download credentials.
4. Checks prerequisites and required tool versions.
5. Authenticates ORAS and Docker to ECR.
6. Enables a Docker wrapper that skips image tags already present in ECR.
7. Locates the airgap binary or offers to download it.
8. Extracts the binary into `AIRGAP_DIR`.
9. Patches the extracted functions for ECR and full destination-path output.
10. Displays the exact image and pack roots.
11. Requires confirmation before any pack or image push.
12. Runs `apply_pack.sh` and `apply_patch.sh`.
13. Creates missing repositories and retries applicable setup failures, up to
    20 attempts.
14. Removes the extraction directory after a successful normal run.

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

The destination is:

```text
<ECR_REGISTRY>/<ECR_BASE_CONTENT_PATH>/<ECR_PACK_BASE>
```

Set `ECR_PACK_BASE="spectro-packs"` in `common-config.sh` when the intended
destination is the standard pack root.

## Use case 4: Download, verify, and push bundles from URLs

Add one URL per line to `zst_urls.txt`. Empty lines and lines beginning with `#`
are ignored. Include both each `.zst` URL and its matching `.sig.bin` URL.

Run:

```bash
./push_from_url.sh ./bundles
```

The script:

1. Downloads listed files into `./bundles/downloads`.
2. Skips files already present locally.
3. Downloads the configured public key if necessary.
4. Verifies each `.zst` against the matching `.sig.bin`.
5. Displays passed and failed signature counts.
6. Authenticates the Palette CLI to ECR.
7. Pushes all downloaded `.zst` files.

This workflow sets `ECR_PACK_BASE="spectro-packs"` internally. Its destination
is:

```text
<ECR_REGISTRY>/<ECR_BASE_CONTENT_PATH>/spectro-packs
```

Important: the current script reports failed or missing signatures but does not
automatically stop before the push. Review the verification results carefully.

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
   ECR_DELETE_PATH="palette-airgap/spectro-packs"
   ```

3. Resolves the full confirmation path as
   `<ECR_REGISTRY>/<ECR_DELETE_PATH>`.
4. Selects only the exact configured repository and repositories below it.
5. Displays every full ECR repository path selected for deletion.
6. Requires the operator to type the complete resolved deletion path.
7. Force-deletes every listed repository and all contained images.

Any confirmation mismatch aborts before deletion.

## Use case 6: Delete a hard-coded repository prefix

`delete_ecr_images-2.sh` uses the account, region, and prefix declared directly
inside that script:

```bash
./delete_ecr_images-2.sh
```

It displays the initial repository list and asks once:

```text
Are you sure you want to delete all of the above? (yes/no):
```

Only the exact response `yes` proceeds. It does not ask again for each
repository. The AWS CLI pager and per-delete JSON responses are suppressed,
while concise deletion progress remains visible.

Use this script only after reviewing its hard-coded `ACCOUNT_ID`, `REGION`, and
`PREFIX`. Its query uses `starts_with`, so similarly named repositories also
match when their names begin with that prefix. Prefer `delete_ecr_images.sh`
when shared configuration should define the target.

## Logs and generated files

`push_to_ecr.sh` writes:

```text
push_to_ecr-<vertex-version>-<YYYYmmddHHMMSS>.log
```

The full console stream is copied to this file. The `.gitignore` excludes these
logs, extracted `spectroairgap-*` directories, the configured airgap binary,
and known bundle artifacts.

The retry helper creates temporary attempt logs under `/tmp`. Successful
attempt logs are removed. Relevant failed output is replayed into the main log.

Downloaded URL bundles are stored beneath:

```text
<bundle-dir>/downloads/
```

## Troubleshooting

### Prerequisite check fails

Follow the OS-specific guidance printed by the script. Confirm versions with:

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

Do not approve the confirmation. Correct `ECR_BASE_CONTENT_PATH`,
`ECR_IMAGE_BASE`, or `ECR_PACK_BASE`, then rerun and review the resolved paths.
