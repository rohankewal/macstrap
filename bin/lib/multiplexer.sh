#!/usr/bin/env bash
# Which terminal multiplexer Macstrap is driving: tmux (classic) or herdr
# (agent multiplexer, https://herdr.dev). The choice is picked once at install
# time, recorded in ~/.macstrap/multiplexer, and read back by theme-set and
# doctor so the rest of the tooling doesn't have to guess.
#
# Requires: log.sh (all functions) and manifest.sh (herdr_apply_theme only).

MACSTRAP_HOME="${MACSTRAP_HOME:-$HOME/.macstrap}"
MACSTRAP_MULTIPLEXER_FILE="$MACSTRAP_HOME/multiplexer"
MACSTRAP_MULTIPLEXERS=(tmux herdr)

# herdr keeps everything in one TOML file; HERDR_CONFIG_PATH is herdr's own
# override, so honour it rather than hardcoding the default location.
HERDR_CONFIG="${HERDR_CONFIG_PATH:-$HOME/.config/herdr/config.toml}"

multiplexer_valid() {
  local candidate="$1" m
  for m in "${MACSTRAP_MULTIPLEXERS[@]}"; do
    [[ "$m" == "$candidate" ]] && return 0
  done
  return 1
}

# multiplexer_get -> the recorded choice, defaulting to tmux. The default
# matters for installs that predate this option: they get tmux, which is what
# they already have wired up. MACSTRAP_MULTIPLEXER overrides for one run,
# which is how `macstrap multiplexer set --dry-run` previews the multiplexer
# it would switch to rather than the one still on disk.
multiplexer_get() {
  local recorded="${MACSTRAP_MULTIPLEXER:-}"
  [[ -z "$recorded" && -f "$MACSTRAP_MULTIPLEXER_FILE" ]] && recorded="$(<"$MACSTRAP_MULTIPLEXER_FILE")"
  if multiplexer_valid "$recorded"; then
    printf '%s' "$recorded"
  else
    printf '%s' "tmux"
  fi
}

multiplexer_set() {
  local choice="$1"
  if ! multiplexer_valid "$choice"; then
    log_error "unknown multiplexer: $choice (choose one of: ${MACSTRAP_MULTIPLEXERS[*]})"
    return 1
  fi
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_dim "  [dry-run] would record multiplexer: $choice"
    return 0
  fi
  mkdir -p "$MACSTRAP_HOME"
  printf '%s\n' "$choice" > "$MACSTRAP_MULTIPLEXER_FILE"
}

# multiplexer_resolve [explicit-choice] -> tmux|herdr, on stdout.
# Precedence: an explicit --multiplexer flag, then whatever is already
# recorded (so re-running the installer never silently re-asks), then an
# interactive prompt, then tmux for non-interactive runs.
multiplexer_resolve() {
  local explicit="${1:-}"

  if [[ -n "$explicit" ]]; then
    multiplexer_valid "$explicit" || {
      log_error "unknown multiplexer: $explicit (choose one of: ${MACSTRAP_MULTIPLEXERS[*]})"
      return 1
    }
    printf '%s' "$explicit"
    return 0
  fi

  if [[ -f "$MACSTRAP_MULTIPLEXER_FILE" ]] && multiplexer_valid "$(<"$MACSTRAP_MULTIPLEXER_FILE")"; then
    printf '%s' "$(<"$MACSTRAP_MULTIPLEXER_FILE")"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    printf '%s' "tmux"
    return 0
  fi

  {
    log_step "Pick a terminal multiplexer"
    log_dim "  tmux   the classic. Themed via a source-file include in ~/.tmux.conf."
    log_dim "  herdr  newer agent multiplexer (herdr.dev): tmux-style prefix keys plus"
    log_dim "         mouse, panes that track what each coding agent is doing, and"
    log_dim "         sessions that survive detach/restart."
    log_dim "  Either way you can switch later with: macstrap multiplexer set <name>"
  } >&2
  prompt_choice "Which one?" "tmux" "${MACSTRAP_MULTIPLEXERS[@]}"
}

# --- herdr theming ----------------------------------------------------------
#
# tmux has `source-file`, so Macstrap can own one small file and leave
# ~/.tmux.conf almost untouched. herdr's config is TOML, which has no include
# directive, so the theme has to live inside the user's own config.toml. It
# goes in as a marked block (the same convention herdr itself uses for its
# agent integrations), which manifest_ensure_block can rewrite on every theme
# switch and `macstrap remove` can reverse.

# True if config.toml declares [theme] / [theme.custom] outside our block.
# Writing our block on top of that would produce a duplicate TOML table, which
# herdr treats as a hard parse error and responds to by discarding the whole
# config — so this is a refuse-to-touch condition, not a warning to power past.
herdr_has_own_theme_table() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  awk -v b="# >>> macstrap theme" -v e="# <<< macstrap theme" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip   { print }
  ' "$file" | grep -qE '^[[:space:]]*\[theme(\]|\.)'
}

herdr_apply_theme() {
  local src="$1" file="$HERDR_CONFIG"

  if [[ ! -f "$src" ]]; then
    log_error "  missing generated herdr config: $src"
    log_dim  "  run scripts/gen-theme-configs.sh to regenerate theme output"
    return 1
  fi

  if herdr_has_own_theme_table "$file"; then
    log_warn "  $file already has its own [theme] section — leaving it alone."
    log_dim  "  TOML has no include directive, and a duplicate [theme] table makes herdr"
    log_dim  "  discard the entire config, so Macstrap won't add its block next to yours."
    log_dim  "  Delete or comment out your [theme] / [theme.custom] tables and re-run"
    log_dim  "  'macstrap theme set <name>' to let Macstrap drive herdr's colors."
    return 0
  fi

  manifest_ensure_block "$file" "theme" "$(<"$src")"
}
