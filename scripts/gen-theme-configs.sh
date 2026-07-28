#!/usr/bin/env bash
# Regenerates every theme's per-app config from its palette.json.
# palette.json is the only file meant to be hand-edited; everything else in
# a theme folder is generated output. Run this after adding/editing a theme.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEMES_DIR="$ROOT/themes"

strip_hash() { printf '%s' "${1#\#}"; }

hex_to_rgb() {
  local hex; hex="$(strip_hash "$1")"
  printf '%d;%d;%d' "$((16#${hex:0:2}))" "$((16#${hex:2:2}))" "$((16#${hex:4:2}))"
}

for dir in "$THEMES_DIR"/*/; do
  theme="$(basename "$dir")"
  palette="$dir/palette.json"
  [[ -f "$palette" ]] || continue

  get() { jq -r ".$1" "$palette"; }

  name=$(get name)
  # herdr only exposes a fixed set of color tokens on top of one of its
  # built-in themes, so each palette names the closest base to override.
  herdr_base=$(get herdr_base); [[ "$herdr_base" == "null" ]] && herdr_base="terminal"
  bg=$(get bg); bg_alt=$(get bg_alt); fg=$(get fg); fg_muted=$(get fg_muted)
  black=$(get black); red=$(get red); green=$(get green); yellow=$(get yellow)
  blue=$(get blue); magenta=$(get magenta); cyan=$(get cyan); white=$(get white)
  accent=$(get accent)

  # bare-hex versions (no '#') — Ghostty's config format uses bare hex throughout
  b_bg=$(strip_hash "$bg"); b_fg=$(strip_hash "$fg"); b_accent=$(strip_hash "$accent")
  b_bg_alt=$(strip_hash "$bg_alt")
  b_black=$(strip_hash "$black"); b_red=$(strip_hash "$red"); b_green=$(strip_hash "$green")
  b_yellow=$(strip_hash "$yellow"); b_blue=$(strip_hash "$blue"); b_magenta=$(strip_hash "$magenta")
  b_cyan=$(strip_hash "$cyan"); b_white=$(strip_hash "$white")

  # --- Ghostty: explicit palette + bg/fg, not a guessed built-in theme name ---
  cat > "$dir/ghostty.conf" <<EOF
# Generated from palette.json for theme: $name — do not hand-edit.
background = $b_bg
foreground = $b_fg
cursor-color = $b_accent
selection-background = $b_bg_alt
selection-foreground = $b_fg
palette = 0=$b_black
palette = 1=$b_red
palette = 2=$b_green
palette = 3=$b_yellow
palette = 4=$b_blue
palette = 5=$b_magenta
palette = 6=$b_cyan
palette = 7=$b_white
palette = 8=$b_black
palette = 9=$b_red
palette = 10=$b_green
palette = 11=$b_yellow
palette = 12=$b_blue
palette = 13=$b_magenta
palette = 14=$b_cyan
palette = 15=$b_fg
EOF

  # --- tmux ---
  cat > "$dir/tmux.conf" <<EOF
# Generated from palette.json for theme: $name — do not hand-edit.
set -g status-style "bg=${bg},fg=${fg}"
set -g status-left-style "bg=${bg},fg=${accent}"
set -g status-right-style "bg=${bg},fg=${fg_muted}"
set -g window-status-current-style "bg=${accent},fg=${bg}"
set -g pane-border-style "fg=${bg_alt}"
set -g pane-active-border-style "fg=${accent}"
set -g message-style "bg=${bg_alt},fg=${fg}"
EOF

  # --- herdr: TOML fragment spliced into the user's config.toml ---
  # These are every token herdr 0.7.5 accepts under [theme.custom] (verified
  # against `herdr config check`, which reports anything else as an unknown
  # key); the rest of the UI comes from the base theme named above.
  cat > "$dir/herdr.toml" <<EOF
# Generated from palette.json for theme: $name — do not hand-edit.
[theme]
name = "$herdr_base"

[theme.custom]
panel_bg = "$bg"
surface_dim = "$bg"
surface0 = "$bg_alt"
text = "$fg"
accent = "$accent"
red = "$red"
green = "$green"
yellow = "$yellow"
blue = "$blue"
mauve = "$magenta"
teal = "$cyan"
peach = "$accent"
EOF

  # --- Neovim: plain data module read by init.lua on startup ---
  cat > "$dir/neovim.lua" <<EOF
-- Generated from palette.json for theme: $name — do not hand-edit.
-- A running Neovim needs :luafile or a restart to pick this up; the TUI
-- picker tells the user this rather than pretending it's instant.
return {
  name = "$theme",
  colors = {
    bg = "$bg", bg_alt = "$bg_alt", fg = "$fg", fg_muted = "$fg_muted",
    black = "$black", red = "$red", green = "$green", yellow = "$yellow",
    blue = "$blue", magenta = "$magenta", cyan = "$cyan", white = "$white",
    accent = "$accent",
  },
}
EOF

  # --- sketchybar: sourced by sketchybarrc, ARGB hex sketchybar expects ---
  cat > "$dir/sketchybar.sh" <<EOF
#!/usr/bin/env bash
# Generated from palette.json for theme: $name — do not hand-edit.
export MACSTRAP_BG="0xff$(strip_hash "$bg")"
export MACSTRAP_FG="0xff$(strip_hash "$fg")"
export MACSTRAP_ACCENT="0xff$(strip_hash "$accent")"
export MACSTRAP_MUTED="0xff$(strip_hash "$fg_muted")"
EOF
  chmod +x "$dir/sketchybar.sh"

  # --- precomputed ANSI swatch for the fzf preview pane (cheap at runtime) ---
  {
    printf '%s\n\n' "$name"
    for c in "$bg" "$red" "$green" "$yellow" "$blue" "$magenta" "$cyan" "$fg"; do
      rgb="$(hex_to_rgb "$c")"
      printf '\033[48;2;%sm  \033[0m' "$rgb"
    done
    printf '\n'
  } > "$dir/preview.ansi"

  echo "generated: $theme"
done
