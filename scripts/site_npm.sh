#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_DIR="${SITE_DIR:-$ROOT_DIR/site}"
NODE_VERSION_FILE="${NODE_VERSION_FILE:-$SITE_DIR/.node-version}"

if [[ ! -f "$NODE_VERSION_FILE" ]]; then
  echo "Missing Node version file: $NODE_VERSION_FILE" >&2
  exit 1
fi

NODE_VERSION="$(tr -d '[:space:]' < "$NODE_VERSION_FILE")"

if [[ -z "$NODE_VERSION" ]]; then
  echo "Node version file is empty: $NODE_VERSION_FILE" >&2
  exit 1
fi

OS_NAME="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH_NAME="$(uname -m)"

case "$OS_NAME/$ARCH_NAME" in
  darwin/arm64)
    NODE_DISTRO="darwin-arm64"
    ;;
  darwin/x86_64)
    NODE_DISTRO="darwin-x64"
    ;;
  linux/x86_64)
    NODE_DISTRO="linux-x64"
    ;;
  linux/aarch64 | linux/arm64)
    NODE_DISTRO="linux-arm64"
    ;;
  *)
    echo "Unsupported platform for site_npm.sh: $OS_NAME/$ARCH_NAME" >&2
    exit 1
    ;;
esac

TOOLCHAIN_DIR="${ROOT_DIR}/build/tooling/node-${NODE_VERSION}-${NODE_DISTRO}"
NODE_BIN="${TOOLCHAIN_DIR}/bin/node"
NPM_BIN="${TOOLCHAIN_DIR}/bin/npm"

install_toolchain() {
  local archive_name="node-${NODE_VERSION}-${NODE_DISTRO}.tar.gz"
  local download_url="https://nodejs.org/dist/${NODE_VERSION}/${archive_name}"
  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' RETURN

  mkdir -p "${ROOT_DIR}/build/tooling"
  curl -fsSL "$download_url" -o "$temp_dir/$archive_name"
  tar -xzf "$temp_dir/$archive_name" -C "$temp_dir"
  rm -rf "$TOOLCHAIN_DIR"
  mv "$temp_dir/node-${NODE_VERSION}-${NODE_DISTRO}" "$TOOLCHAIN_DIR"
}

if [[ ! -x "$NODE_BIN" || ! -x "$NPM_BIN" ]]; then
  install_toolchain
fi

export PATH="${TOOLCHAIN_DIR}/bin:$PATH"
exec "$NPM_BIN" --prefix "$SITE_DIR" "$@"
