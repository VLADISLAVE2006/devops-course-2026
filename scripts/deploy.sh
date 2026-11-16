#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
ROOT="$(git rev-parse --show-toplevel)"
DRY=()
case "${1:-}" in
    '') [[ $# -eq 0 ]] || exit 1 ;;
    --dry-run) [[ $# -eq 1 ]] || exit 1; DRY=(--dry-run) ;;
    *) echo 'Usage: scripts/deploy.sh [--dry-run]' >&2; exit 1 ;;
esac
[[ -f "$ROOT/site/index.html" ]] || { echo 'site/index.html is missing' >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit changes before deploying' >&2; exit 1; }
if ! rsync -avz --delete --chmod=D755,F644 "${DRY[@]}" \
    -e 'ssh -o BatchMode=yes -o ConnectTimeout=5' \
    "$ROOT/site/" devops:/var/www/devops-site/; then
    echo 'File delivery failed' >&2
    exit 1
fi
if [[ ${#DRY[@]} -eq 0 ]]; then
    if ! curl --fail --silent --show-error --connect-timeout 5 --max-time 15 \
        --cacert "${HOME}/devops.crt" https://devops.local/ >/dev/null; then
        echo 'Resource availability check failed' >&2
        exit 1
    fi
fi
printf 'Commit: %s\n' "$(git rev-parse --short HEAD)"
