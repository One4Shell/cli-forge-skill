#!/usr/bin/env bash
# install.sh -- installs the cli-forge-skill into a project without requiring npm.
#
# Usage:
#   ./install.sh [--dir <path>] [--path <path>] [--claude] [--force]
#   curl -fsSL https://raw.githubusercontent.com/One4Shell/cli-forge-skill/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/One4Shell/cli-forge-skill/main/install.sh | bash -s -- --claude
set -euo pipefail

REPO_SLUG="${CLI_FORGE_SKILL_REPO:-One4Shell/cli-forge-skill}"
REPO_BRANCH="${CLI_FORGE_SKILL_BRANCH:-main}"

TARGET_DIR="$(pwd)"
INSTALL_PATH=".agents/skills/cli-forge-skill"
FORCE=0

usage() {
  cat <<'EOF'
Usage: install.sh [options]

Options:
  --dir <path>     Project root to install into (default: current directory)
  --path <path>    Custom install path, relative to --dir
                    (default: .agents/skills/cli-forge-skill)
  --claude         Shorthand for --path .claude/skills/cli-forge-skill
  --force          Overwrite existing files (default: skip files that already exist)
  -h, --help       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) TARGET_DIR="$2"; shift 2 ;;
    --path) INSTALL_PATH="$2"; shift 2 ;;
    --claude) INSTALL_PATH=".claude/skills/cli-forge-skill"; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

DEST="${TARGET_DIR%/}/${INSTALL_PATH}"
mkdir -p "$DEST"

copy_tree() {
  local src="$1" dst="$2"
  mkdir -p "$dst"
  while IFS= read -r -d '' file; do
    local rel="${file#"$src"/}"
    local out="$dst/$rel"
    mkdir -p "$(dirname "$out")"
    if [[ -e "$out" && $FORCE -eq 0 ]]; then
      echo "skip (exists): $rel"
    else
      cp "$file" "$out"
      echo "install: $rel"
    fi
  done < <(find "$src" -type f -print0)
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
LOCAL_SRC="${SCRIPT_DIR}/skills/cli-forge-skill"

if [[ -d "$LOCAL_SRC" ]]; then
  # Running from a local checkout -- no network needed.
  copy_tree "$LOCAL_SRC" "$DEST"
else
  # Running via curl | bash -- fetch a tarball of just this subtree.
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  echo "Fetching ${REPO_SLUG}@${REPO_BRANCH}..."
  curl -fsSL "https://codeload.github.com/${REPO_SLUG}/tar.gz/refs/heads/${REPO_BRANCH}" \
    -o "$TMP/cli-forge-skill.tar.gz"
  tar -xzf "$TMP/cli-forge-skill.tar.gz" -C "$TMP"
  REPO_ROOT="$(find "$TMP" -maxdepth 1 -type d -name '*-*' | head -n1)"
  copy_tree "${REPO_ROOT}/skills/cli-forge-skill" "$DEST"
fi

echo
echo "cli-forge-skill installed to: $DEST"
