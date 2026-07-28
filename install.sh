#!/usr/bin/env bash
# Macstrap installer.
#
# Design rules this script follows (see README for the why):
#   - every symlink/config change goes through manifest.sh, so it's
#     idempotent, backed-up, and reversible via `macstrap remove`
#   - the one genuinely irreversible step (yabai's scripting addition,
#     which needs a partial SIP disable) is never run without an explicit,
#     freshly-asked confirmation — it is not part of the automatic flow
#   - safe to run more than once
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/lib/log.sh
source "$ROOT/bin/lib/log.sh"
# shellcheck source=bin/lib/manifest.sh
source "$ROOT/bin/lib/manifest.sh"
# shellcheck source=bin/lib/multiplexer.sh
source "$ROOT/bin/lib/multiplexer.sh"
# shellcheck source=bin/lib/shell.sh
source "$ROOT/bin/lib/shell.sh"

MULTIPLEXER_FLAG=""
SHELL_FLAG=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) export DRY_RUN=1 ;;
    --multiplexer=*) MULTIPLEXER_FLAG="${arg#*=}" ;;
    --shell=*) SHELL_FLAG="${arg#*=}" ;;
    *) log_error "unknown flag: $arg"; exit 1 ;;
  esac
done

if [[ "$(uname)" != "Darwin" ]]; then
  log_error "Macstrap only runs on macOS."
  exit 1
fi

log_step "Macstrap install starting$( [[ "${DRY_RUN:-0}" == "1" ]] && echo " (dry run)" )"
manifest_init

# ---------------------------------------------------------------------------
# 1. Homebrew
# ---------------------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
  log_step "Homebrew not found."
  if confirm "Install Homebrew now (runs the official install script)?"; then
    [[ "${DRY_RUN:-0}" == "1" ]] || /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    log_error "Homebrew is required. Install it yourself and re-run."
    exit 1
  fi
fi
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"

# ---------------------------------------------------------------------------
# 2. The two choices (asked once, then remembered)
# ---------------------------------------------------------------------------
MULTIPLEXER="$(multiplexer_resolve "$MULTIPLEXER_FLAG")"
multiplexer_set "$MULTIPLEXER"
log_step "Multiplexer: $MULTIPLEXER"

MACSTRAP_SHELL_CHOICE="$(shell_resolve "$SHELL_FLAG")"
shell_set "$MACSTRAP_SHELL_CHOICE"
log_step "Shell: $MACSTRAP_SHELL_CHOICE"

# ---------------------------------------------------------------------------
# 3. Core packages, plus whatever the two choices above need
# ---------------------------------------------------------------------------
log_step "Installing core packages via Homebrew Bundle..."
bundles=("$ROOT/brew/Brewfile.core" "$ROOT/brew/Brewfile.$MULTIPLEXER")
# omz isn't a Homebrew package — it has its own installer, run further down.
case "$MACSTRAP_SHELL_CHOICE" in
  fish|nushell) bundles+=("$ROOT/brew/Brewfile.$MACSTRAP_SHELL_CHOICE") ;;
esac
for bundle in "${bundles[@]}"; do
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    brew bundle check --file="$bundle" || log_dim "  [dry-run] would run: brew bundle --file=$bundle"
  else
    brew bundle --file="$bundle"
  fi
done

if [[ "$MACSTRAP_SHELL_CHOICE" == "omz" ]]; then
  omz_install
fi

# ---------------------------------------------------------------------------
# 4. Stable ~/.macstrap paths (so configs can reference an absolute path
#    that doesn't depend on where this repo happens to live)
# ---------------------------------------------------------------------------
log_step "Linking Macstrap into ~/.macstrap..."
manifest_link "$HOME/.macstrap/bin" "$ROOT/bin"

# ---------------------------------------------------------------------------
# 5. Base (non-theme) app configs
# ---------------------------------------------------------------------------
log_step "Linking base configs..."
manifest_link "$HOME/.config/skhd/skhdrc"                "$ROOT/configs/skhd/skhdrc"
manifest_link "$HOME/.config/yabai/yabairc"               "$ROOT/configs/yabai/yabairc"
manifest_link "$HOME/.config/sketchybar/sketchybarrc"     "$ROOT/configs/sketchybar/sketchybarrc"
manifest_link "$HOME/.config/sketchybar/plugins"          "$ROOT/configs/sketchybar/plugins"
manifest_link "$HOME/.config/nvim/lua/macstrap/init.lua"  "$ROOT/configs/nvim/lua/macstrap/init.lua"
manifest_link "$HOME/.config/nvim/after/plugin/macstrap.lua" "$ROOT/configs/nvim/after-plugin-macstrap.lua"
manifest_link "$HOME/.config/karabiner/assets/complex_modifications/macstrap-hyper-key.json" \
              "$ROOT/configs/karabiner/macstrap-hyper-key.json"

chmod +x "$ROOT/configs/yabai/yabairc" "$ROOT/configs/sketchybar/sketchybarrc" \
         "$ROOT/configs/sketchybar/plugins/"*.sh 2>/dev/null || true

# ---------------------------------------------------------------------------
# 6. Hook theme includes into Ghostty + the multiplexer without owning their
#    whole config
# ---------------------------------------------------------------------------
log_step "Wiring theme includes into Ghostty + $MULTIPLEXER..."
# NOTE: verify `config-file` is still Ghostty's current include directive
# name/relative-path behavior against the installed version before shipping.
manifest_ensure_line "$HOME/.config/ghostty/config" "config-file = macstrap-theme.conf"

case "$MULTIPLEXER" in
  tmux)
    manifest_ensure_line "$HOME/.tmux.conf" "source-file $HOME/.config/tmux/macstrap-theme.conf"
    ;;
  herdr)
    # Nothing to hook: herdr's config is a single TOML file with no include
    # directive, so theme-set splices a marked block into it instead.
    log_dim "  herdr has no include directive — its theme goes in as a marked block"
    log_dim "  in $HERDR_CONFIG, rewritten on every theme switch."
    ;;
esac

# ---------------------------------------------------------------------------
# 7. Shell: generate Macstrap's fragment and hook it into the chosen shell
# ---------------------------------------------------------------------------
if [[ "$MACSTRAP_SHELL_CHOICE" == "none" ]]; then
  log_step "Shell: leaving your shell alone (pick one later with 'macstrap shell set')"
else
  log_step "Wiring Homebrew's env + starship into $MACSTRAP_SHELL_CHOICE..."
  shell_write_fragment "$MACSTRAP_SHELL_CHOICE"
  shell_wire "$MACSTRAP_SHELL_CHOICE"
  shell_set_login "$(shell_login_path "$MACSTRAP_SHELL_CHOICE")"
fi

# ---------------------------------------------------------------------------
# 8. Apply a default theme so first boot isn't unstyled
# ---------------------------------------------------------------------------
if [[ ! -f "${MACSTRAP_HOME:-$HOME/.macstrap}/current-theme" ]]; then
  log_step "Applying default theme (catppuccin-mocha)..."
  DRY_RUN="${DRY_RUN:-0}" "$ROOT/bin/theme-set" catppuccin-mocha
fi

# ---------------------------------------------------------------------------
# 9. yabai scripting addition — the one irreversible step, gated explicitly
# ---------------------------------------------------------------------------
echo ""
log_step "Optional: yabai's scripting addition (window borders, opacity, full control)"
log_dim "  This requires partially disabling System Integrity Protection and a"
log_dim "  reboot into Recovery Mode. It is NOT required for basic tiling/focus."
log_dim "  It also can't be fully automated here — you'll still need to add a"
log_dim "  sudoers rule yourself so yabai can load it without a password prompt."
if [[ "${DRY_RUN:-0}" != "1" ]] && confirm "Show me the SIP + sudoers steps now?"; then
  cat <<EOF

  1. Reboot into Recovery Mode (hold power button on Apple Silicon, or
     Cmd+R on Intel at startup), then in Terminal there run:
       csrutil enable --without debug --without fs

  2. Reboot normally, then run:
       sudo yabai --install-sa

  3. Add a NOPASSWD sudoers rule so yabairc can reload it silently:
       sudo visudo -f /etc/sudoers.d/yabai
     and add the line printed by:
       yabai --install-sa --print-sudoers   # if unsupported on your version,
                                             # see yabai's wiki for the exact
                                             # sha256-pinned sudoers line

  None of the above has been run automatically.
EOF
fi

# ---------------------------------------------------------------------------
# 10. Start services + cleanup
# ---------------------------------------------------------------------------
log_step "Starting services..."
if [[ "${DRY_RUN:-0}" != "1" ]]; then
  brew services restart yabai      >/dev/null 2>&1 || true
  brew services restart skhd       >/dev/null 2>&1 || true
  brew services restart sketchybar >/dev/null 2>&1 || true
fi
if [[ "$MULTIPLEXER" == "herdr" ]]; then
  # Deliberately not started as a service: herdr spins up its own server the
  # first time you run it. The service only exists to keep sessions alive
  # across reboots, which is a bigger footprint than Macstrap should opt you
  # into.
  log_dim "  herdr starts on demand — run 'herdr'. For sessions that survive a"
  log_dim "  reboot: brew services start herdr"
fi

log_step "Cleaning up Homebrew cache..."
[[ "${DRY_RUN:-0}" == "1" ]] || brew cleanup -s >/dev/null 2>&1 || true

echo ""
log_success "Macstrap installed."
log_dim "  Next: open Karabiner-Elements > Complex Modifications > Add rule, and"
log_dim "  enable 'Macstrap Hyper Key' (macOS requires this one manual click —"
log_dim "  Karabiner's config isn't safe to script-edit directly)."
log_dim "  Then: macstrap doctor    (health check)"
log_dim "        macstrap theme     (pick a different theme)"
