#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
REMOTE=devops
REMOTE_DIR=/var/www/devops-site/
SITE_URL=https://devops.local
CA_CERT="${HOME}/devops.crt"
dry=()
if [[ $# -gt 1 ]] || [[ $# -eq 1 && "$1" != --dry-run ]]; then echo "Usage: $0 [--dry-run]" >&2; exit 1; fi
if [[ ${1:-} == --dry-run ]]; then dry=(--dry-run); fi
if [[ ! -f "$ROOT/site/index.html" ]]; then echo "Missing site/index.html; deployment refused" >&2; exit 1; fi
if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then echo "Repository has uncommitted changes; deployment refused" >&2; exit 1; fi
rsync -avz --delete --chmod=D755,F644 "${dry[@]}" -e "ssh -o BatchMode=yes -o ConnectTimeout=5" "$ROOT/site/" "$REMOTE:$REMOTE_DIR"
if [[ ${1:-} == --dry-run ]]; then echo "Dry run complete"; exit 0; fi
curl --noproxy '*' --fail --silent --show-error --cacert "$CA_CERT" "$SITE_URL" > /dev/null
printf 'Deployed commit %s\n' "$(git -C "$ROOT" rev-parse --short HEAD)"
