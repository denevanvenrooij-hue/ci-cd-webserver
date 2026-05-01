#!/usr/bin/env bash
set -euo pipefail

GITHUB_REPO="xxx"

RUN=false
EXPORT=false
for arg in "$@"; do
  case "$arg" in
    --run) RUN=true ;;
    --export) EXPORT=true ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# Get variables for local testing with Docker run

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="$SCRIPT_DIR/secret/oauth-secrets.json"
GITHUB_TOKEN_FILE="${SCRIPT_DIR}/secret/github.json"

# Redirect URI
REDIRECT_URI="http://sso.poc.test.ubiops.io/oauth2/callback"

CLIENT_ID=$(jq -r '.web.client_id' "$SECRETS_FILE")
CLIENT_SECRET=$(jq -r '.web.client_secret' "$SECRETS_FILE")
COOKIE_SECRET=$(python3 -c 'import secrets; print(secrets.token_hex(16))')

GITHUB_TOKEN=$(jq -r '.token' "${GITHUB_TOKEN_FILE}")


IMAGE=ubiops-static-website

docker build \
  --build-arg GITHUB_REPO=${GITHUB_REPO} \
  --platform linux/amd64 \
  -t "$IMAGE" .

if [[ "$EXPORT" == true ]]; then
  docker save -o "${IMAGE}.tar" "$IMAGE"
fi

if [[ "$RUN" == true ]]; then
  docker run --rm -it \
    --platform linux/amd64 \
    -p 80:8080 \
    -e "OAUTH2_PROXY_CLIENT_ID=${CLIENT_ID}" \
    -e "OAUTH2_PROXY_CLIENT_SECRET=${CLIENT_SECRET}" \
    -e "OAUTH2_PROXY_COOKIE_SECRET=${COOKIE_SECRET}" \
    -e "OAUTH2_PROXY_REDIRECT_URL=${REDIRECT_URI}" \
    -e "GITHUB_TOKEN=${GITHUB_TOKEN}" \
    "$IMAGE"
fi
