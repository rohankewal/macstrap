#!/usr/bin/env bash
# Macstrap's safety layer: every state-changing action goes through here so
# install/theme-set stay idempotent and `macstrap remove` can reverse exactly
# what was done, instead of guessing.
#
# Requires: jq

MACSTRAP_HOME="${MACSTRAP_HOME:-$HOME/.macstrap}"
MACSTRAP_BACKUPS="$MACSTRAP_HOME/backups"
MACSTRAP_MANIFEST="$MACSTRAP_HOME/state.jsonl"
DRY_RUN="${DRY_RUN:-0}"

manifest_init() {
  mkdir -p "$MACSTRAP_BACKUPS"
  touch "$MACSTRAP_MANIFEST"
}

# _manifest_backup_path <file> -> a backup path that isn't already taken.
# Timestamps alone collide: two writes to the same file inside one second
# (a theme switch, a shell switch) would otherwise reuse the same name, and
# the second backup would overwrite the first — leaving `macstrap remove`
# restoring a half-Macstrapped file instead of the original.
_manifest_backup_path() {
  local file="$1" stamp base candidate n=0
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  base="$MACSTRAP_BACKUPS/$stamp-$(basename "$file")"
  candidate="$base"
  while [[ -e "$candidate" ]]; do
    n=$((n + 1))
    candidate="$base.$n"
  done
  printf '%s' "$candidate"
}

_manifest_append() {
  # $1 = json object (already encoded)
  [[ "$DRY_RUN" == "1" ]] && return 0
  printf '%s\n' "$1" >> "$MACSTRAP_MANIFEST"
}

# manifest_link <target> <source>
# Symlinks target -> source. If target exists and is a real file/dir (not
# already our symlink), it is backed up first, never overwritten in place.
# Safe to call repeatedly: a no-op if target already points at source.
manifest_link() {
  local target="$1" source="$2" backup=""

  if [[ -L "$target" ]]; then
    if [[ "$(readlink "$target")" == "$source" ]]; then
      log_dim "  already linked: $target"
      return 0
    fi
    [[ "$DRY_RUN" == "1" ]] || rm -f "$target"
  elif [[ -e "$target" ]]; then
    backup="$(_manifest_backup_path "$target")"
    log_warn "  backing up existing $target -> $backup"
    [[ "$DRY_RUN" == "1" ]] || mv "$target" "$backup"
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log_dim "  [dry-run] would link $target -> $source"
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  ln -s "$source" "$target"
  log_success "  linked $target -> $source"

  _manifest_append "$(jq -nc \
    --arg action "link" \
    --arg target "$target" \
    --arg source "$source" \
    --arg backup "$backup" \
    --arg ts "$(date -u +%FT%TZ)" \
    '{action:$action, target:$target, source:$source, backup:$backup, ts:$ts}')"
}

# manifest_defaults_write <domain> <key> <type> <value>
# Wraps `defaults write`, capturing the previous value first so it can be
# restored on `macstrap remove`. type is a defaults(1) type flag, e.g. -bool.
manifest_defaults_write() {
  local domain="$1" key="$2" type="$3" value="$4"
  local previous
  previous="$(defaults read "$domain" "$key" 2>/dev/null || echo "__unset__")"

  if [[ "$DRY_RUN" == "1" ]]; then
    log_dim "  [dry-run] would set $domain $key -> $value (was: $previous)"
    return 0
  fi

  defaults write "$domain" "$key" "$type" "$value"
  log_success "  set $domain $key -> $value"

  _manifest_append "$(jq -nc \
    --arg action "defaults" \
    --arg domain "$domain" \
    --arg key "$key" \
    --arg type "$type" \
    --arg previous "$previous" \
    --arg value "$value" \
    --arg ts "$(date -u +%FT%TZ)" \
    '{action:$action, domain:$domain, key:$key, type:$type, previous:$previous, value:$value, ts:$ts}')"
}

# manifest_ensure_line <file> <line>
# Appends <line> to <file> if it isn't already present verbatim. Used to hook
# Macstrap's theme include into an existing config (Ghostty, tmux) without
# ever owning or overwriting the user's whole file.
manifest_ensure_line() {
  local file="$1" line="$2" backup=""

  if grep -qxF "$line" "$file" 2>/dev/null; then
    log_dim "  already present in $file"
    return 0
  fi

  # Nothing above this point may create the file: a dry run has to be able to
  # report on a config that doesn't exist yet without bringing it into being.
  if [[ "$DRY_RUN" == "1" ]]; then
    log_dim "  [dry-run] would append to $file: $line"
    return 0
  fi

  mkdir -p "$(dirname "$file")"
  touch "$file"

  backup="$(_manifest_backup_path "$file")"
  cp "$file" "$backup"
  printf '\n%s\n' "$line" >> "$file"
  log_success "  ensured line in $file"

  _manifest_append "$(jq -nc \
    --arg action "append_line" \
    --arg file "$file" \
    --arg line "$line" \
    --arg backup "$backup" \
    --arg ts "$(date -u +%FT%TZ)" \
    '{action:$action, file:$file, line:$line, backup:$backup, ts:$ts}')"
}

# manifest_ensure_block <file> <id> <content>
# Maintains a Macstrap-owned, marker-delimited block inside someone else's
# config file. Unlike manifest_ensure_line this is rewritable: the previous
# copy of the block is replaced, so a value that changes over time (herdr's
# theme colors, which can't be a symlinked include because TOML has no
# include directive) doesn't accumulate stale duplicates.
manifest_ensure_block() {
  local file="$1" id="$2" content="$3" backup=""
  local begin="# >>> macstrap $id" end="# <<< macstrap $id"
  local stripped current new

  # Everything except a previous copy of this block. A missing file reads as
  # empty (so a dry run never has to create one just to describe it) — hence
  # the `|| true`, without which awk's exit status would trip callers' set -e.
  stripped="$(awk -v b="$begin" -v e="$end" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip   { print }
  ' "$file" 2>/dev/null || true)"

  if [[ -n "$stripped" ]]; then
    new="$stripped"$'\n\n'"$begin"$'\n'"$content"$'\n'"$end"
  else
    new="$begin"$'\n'"$content"$'\n'"$end"
  fi

  current="$(cat "$file" 2>/dev/null || true)"
  if [[ "$current" == "$new" ]]; then
    log_dim "  $id block already current in $file"
    return 0
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log_dim "  [dry-run] would write the '$id' block into $file"
    return 0
  fi

  mkdir -p "$(dirname "$file")"
  touch "$file"
  backup="$(_manifest_backup_path "$file")"
  cp "$file" "$backup"
  printf '%s\n' "$new" > "$file"
  log_success "  wrote $id block into $file"

  _manifest_append "$(jq -nc \
    --arg action "block" \
    --arg file "$file" \
    --arg id "$id" \
    --arg backup "$backup" \
    --arg ts "$(date -u +%FT%TZ)" \
    '{action:$action, file:$file, id:$id, backup:$backup, ts:$ts}')"
}

# manifest_remove_block <file> <id>
# Drops a block written by manifest_ensure_block, leaving the rest of the file
# alone. Used when Macstrap stops managing a config it doesn't own (switching
# multiplexers), so it can't leave a block behind that silently goes stale.
manifest_remove_block() {
  local file="$1" id="$2" backup=""
  local begin="# >>> macstrap $id" end="# <<< macstrap $id"
  local stripped

  [[ -f "$file" ]] || return 0
  grep -qxF "$begin" "$file" || return 0

  if [[ "$DRY_RUN" == "1" ]]; then
    log_dim "  [dry-run] would remove the '$id' block from $file"
    return 0
  fi

  stripped="$(awk -v b="$begin" -v e="$end" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip   { print }
  ' "$file")"

  backup="$(_manifest_backup_path "$file")"
  cp "$file" "$backup"
  printf '%s\n' "$stripped" > "$file"
  log_success "  removed $id block from $file"

  _manifest_append "$(jq -nc \
    --arg action "block" \
    --arg file "$file" \
    --arg id "$id" \
    --arg backup "$backup" \
    --arg ts "$(date -u +%FT%TZ)" \
    '{action:$action, file:$file, id:$id, backup:$backup, ts:$ts}')"
}

# manifest_remove_line <file> <line>
# Deletes a line manifest_ensure_line put there, leaving the rest alone. Used
# when Macstrap stops managing a config it doesn't own.
manifest_remove_line() {
  local file="$1" line="$2" backup="" stripped

  [[ -f "$file" ]] || return 0
  grep -qxF "$line" "$file" 2>/dev/null || return 0

  if [[ "$DRY_RUN" == "1" ]]; then
    log_dim "  [dry-run] would remove from $file: $line"
    return 0
  fi

  stripped="$(grep -vxF "$line" "$file" || true)"
  backup="$(_manifest_backup_path "$file")"
  cp "$file" "$backup"
  printf '%s\n' "$stripped" > "$file"
  log_success "  removed our line from $file"

  _manifest_append "$(jq -nc \
    --arg action "remove_line" \
    --arg file "$file" \
    --arg line "$line" \
    --arg backup "$backup" \
    --arg ts "$(date -u +%FT%TZ)" \
    '{action:$action, file:$file, line:$line, backup:$backup, ts:$ts}')"
}

# manifest_unlink <target>
# Removes a symlink Macstrap created, recording where it pointed. Reversing an
# unlink re-creates the link, which then lets the original link entry — further
# back in the manifest — restore whatever it had backed up.
manifest_unlink() {
  local target="$1" source_path=""

  [[ -L "$target" ]] || return 0
  source_path="$(readlink "$target")"

  if [[ "$DRY_RUN" == "1" ]]; then
    log_dim "  [dry-run] would remove symlink $target"
    return 0
  fi

  rm -f "$target"
  log_success "  removed symlink $target"

  _manifest_append "$(jq -nc \
    --arg action "unlink" \
    --arg target "$target" \
    --arg source "$source_path" \
    --arg ts "$(date -u +%FT%TZ)" \
    '{action:$action, target:$target, source:$source, ts:$ts}')"
}

# manifest_chsh <target-shell> <previous-shell>
# Changes the login shell, remembering the old one. The target must already be
# listed in /etc/shells — getting it there is the caller's problem, because
# that is the one step here that needs sudo.
manifest_chsh() {
  local target="$1" previous="$2"

  if [[ "$DRY_RUN" == "1" ]]; then
    log_dim "  [dry-run] would change login shell to $target (was: ${previous:-unknown})"
    return 0
  fi

  if ! chsh -s "$target"; then
    log_error "  chsh failed — login shell unchanged"
    return 0
  fi
  log_success "  login shell is now $target (was: ${previous:-unknown})"
  log_dim "  open a new terminal window for it to take effect"

  _manifest_append "$(jq -nc \
    --arg action "shell" \
    --arg target "$target" \
    --arg previous "$previous" \
    --arg ts "$(date -u +%FT%TZ)" \
    '{action:$action, target:$target, previous:$previous, ts:$ts}')"
}

# manifest_reverse: walk the manifest backwards and undo each recorded action.
manifest_reverse() {
  [[ -f "$MACSTRAP_MANIFEST" ]] || { log_warn "no manifest found, nothing to reverse"; return 0; }

  tac "$MACSTRAP_MANIFEST" 2>/dev/null || tail -r "$MACSTRAP_MANIFEST"
}

manifest_each_reversed() {
  # portable reverse-line-read (tac isn't on macOS by default; tail -r is)
  tail -r "$MACSTRAP_MANIFEST" 2>/dev/null || tac "$MACSTRAP_MANIFEST"
}
