#!/usr/bin/env bash
# Shared pretty-output helpers. Source, don't execute.

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_BOLD=$'\033[1m'
else
  C_RESET=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""
fi

log_step()    { printf '%s==>%s %s\n' "$C_BLUE$C_BOLD" "$C_RESET" "$1"; }
log_success() { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
log_warn()    { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
log_error()   { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; }
log_dim()     { printf '%s%s%s\n' "$C_DIM" "$1" "$C_RESET"; }

confirm() {
  # confirm "question" -> 0 (yes) / 1 (no). Defaults to no.
  local reply
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

prompt_choice() {
  # prompt_choice "question" <default> <option>... -> chosen option on stdout.
  # Re-asks until the answer is one of the options; empty input takes the
  # default. read's prompt and log_error both go to stderr, so stdout carries
  # nothing but the answer and callers can capture it.
  local question="$1" default="$2"; shift 2
  local options=("$@") reply opt

  while true; do
    # EOF (Ctrl-D) or no usable terminal takes the default rather than looping.
    if ! read -r -p "$question [$(IFS=/; echo "${options[*]}")] ($default) " reply </dev/tty; then
      printf '%s' "$default"
      return 0
    fi
    reply="${reply:-$default}"
    for opt in "${options[@]}"; do
      if [[ "$reply" == "$opt" ]]; then
        printf '%s' "$opt"
        return 0
      fi
    done
    log_error "not one of: ${options[*]}"
  done
}
