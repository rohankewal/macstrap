#!/usr/bin/env bash
# Regenerates the terminal images in docs/media/ from real command output.
#
# Nothing here changes your system: every command it runs is either read-only
# (--help, theme list, doctor) or a --dry-run. It runs each one under `script`
# so the tools see a TTY and emit their real colors, then renders the captured
# ANSI to SVG.
#
# Run it from a checkout at ~/macstrap if you want the paths in the images to
# match what the README tells people to do.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/docs/media"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OUT"

# Homebrew's auto-update banner and env hints are noise from another tool, and
# they'd date the images every time Homebrew changes its wording.
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1

# capture <name> <command...> — under a PTY, with stdin closed so nothing hangs
# waiting for input that a non-interactive run will never get.
capture() {
  local name="$1"; shift
  script -q /dev/null "$@" > "$TMP/$name.raw" 2>&1 </dev/null || true
}

cd "$ROOT"
capture help    ./bin/macstrap --help
capture install ./install.sh --dry-run --multiplexer=herdr --shell=fish
capture themes  ./bin/macstrap theme list
capture doctor  ./bin/macstrap-doctor

render() {
  python3 "$ROOT/scripts/ansi-to-svg.py" "$TMP/$1.raw" "$OUT/$1.svg" --title "$2" --cols "${3:-104}"
}

render help    "macstrap --help"                                  84
render install "./install.sh --dry-run --multiplexer=herdr --shell=fish" 118
render themes  "macstrap theme list"                              62
render doctor  "macstrap doctor"                                  78

echo "wrote SVGs to $OUT"
