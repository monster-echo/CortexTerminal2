#!/usr/bin/env bash
# 把最新（或指定）worker release 的二进制拉进 assets/bin，供本地构建/调试。
# CI 不用本脚本 —— worker-ui-release.yml 在构建时自己下载。
#
# 用法:
#   tool/fetch_worker.sh [worker-vX.Y.Z]
#
# 本地访问 GitHub 需要代理时:
#   HTTPS_PROXY=http://127.0.0.1:7897 tool/fetch_worker.sh
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="monster-echo/CortexTerminal2"

tag="${1:-}"
if [ -z "$tag" ]; then
  tag=$(gh api "repos/$REPO/releases" --paginate --jq '
    [.[].tag_name
      | select(test("^worker-v[0-9]+\\.[0-9]+\\.[0-9]+$"))
      | {tag: ., parts: (ltrimstr("worker-v") | split(".") | map(tonumber))}]
    | sort_by(.parts) | last | .tag')
  test -n "$tag" || { echo "error: no worker-v* release found" >&2; exit 1; }
fi

case "$(uname -m)" in
  arm64) asset="corterm-osx-arm64.tar.gz" ;;
  x86_64) asset="corterm-osx-x64.tar.gz" ;;
  *) echo "error: unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

echo "fetching $tag ($asset)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
gh release download "$tag" --repo "$REPO" --pattern "$asset" --dir "$tmp"
tar -xzf "$tmp/$asset" -C "$tmp"

mkdir -p assets/bin
cp "$tmp/corterm" "$tmp/appsettings.json" assets/bin/
chmod +x assets/bin/corterm

# 自证：拉下来的二进制能跑，且版本与 tag 一致
version=$(assets/bin/corterm --version | head -n1)
echo "bundled worker: $version ($tag)"
case "$version" in
  "${tag#worker-v}"|"${tag#worker-v}"-*|"${tag#worker-v}"+*) ;;
  *) echo "error: version mismatch: $version vs $tag" >&2; exit 1 ;;
esac
