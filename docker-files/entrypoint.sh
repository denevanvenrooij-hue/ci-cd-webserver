#!/bin/sh
set -e

WEBROOT="/usr/share/nginx/html"
CLONE_DIR="/tmp/site-repo"

# --- Validation: GitHub ---
if [ -z "${GITHUB_REPO}" ]; then
  echo "ERROR: GITHUB_REPO is not set."
  echo "  Set it as a build arg (docker build --build-arg GITHUB_REPO=...) or at runtime (-e GITHUB_REPO=...)."
  exit 1
fi

if [ -z "${GITHUB_TOKEN}" ]; then
  echo "ERROR: GITHUB_TOKEN is not set. A personal access token is required."
  exit 1
fi

# --- Validation: OAuth2 proxy secrets ---
if [ -z "${OAUTH2_PROXY_CLIENT_ID}" ]; then
  echo "ERROR: OAUTH2_PROXY_CLIENT_ID is not set."
  exit 1
fi

if [ -z "${OAUTH2_PROXY_CLIENT_SECRET}" ]; then
  echo "ERROR: OAUTH2_PROXY_CLIENT_SECRET is not set."
  exit 1
fi

if [ -z "${OAUTH2_PROXY_COOKIE_SECRET}" ]; then
  echo "ERROR: OAUTH2_PROXY_COOKIE_SECRET is not set."
  echo "  Generate one with: python3 -c 'import secrets; print(secrets.token_hex(16))'"
  exit 1
fi

if [ -z "${OAUTH2_PROXY_REDIRECT_URL}" ]; then
  echo "ERROR: OAUTH2_PROXY_REDIRECT_URL is not set."
  echo "  Example: https://yourdomain.com/oauth2/callback"
  exit 1
fi

BRANCH="${GITHUB_BRANCH:-main}"

# Inject token into the HTTPS URL
# Supports:  https://github.com/org/repo.git
CLONE_URL=$(echo "${GITHUB_REPO}" | sed "s|https://|https://${GITHUB_TOKEN}@|")

echo "Cloning ${GITHUB_REPO} (branch: ${BRANCH})..."
rm -rf "${CLONE_DIR}"
git clone --depth=1 --branch "${BRANCH}" "${CLONE_URL}" "${CLONE_DIR}"

echo "Deploying site to ${WEBROOT}..."
cp -rf "${CLONE_DIR}/." "${WEBROOT}/"
rm -rf "${WEBROOT}/.git" 2>/dev/null || true

# Clean up clone dir
rm -rf "${CLONE_DIR}"

echo "Starting oauth2-proxy..."
oauth2-proxy \
  --redirect-url="${OAUTH2_PROXY_REDIRECT_URL}" \
  &

echo "Site deployed. Starting nginx..."
exec nginx -g "daemon off;"
