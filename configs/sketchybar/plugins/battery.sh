#!/usr/bin/env bash
BATT_INFO="$(pmset -g batt)"
PERCENTAGE="$(echo "$BATT_INFO" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')"
CHARGING="$(echo "$BATT_INFO" | grep 'AC Power')"

[[ -z "$PERCENTAGE" ]] && exit 0

case "${PERCENTAGE}" in
  9[0-9]|100) ICON="" ;;
  [6-8][0-9]) ICON="" ;;
  [3-5][0-9]) ICON="" ;;
  [1-2][0-9]) ICON="" ;;
  *)          ICON="" ;;
esac

[[ -n "$CHARGING" ]] && ICON=""

sketchybar --set "$NAME" icon="$ICON" label="${PERCENTAGE}%"
