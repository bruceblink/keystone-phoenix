#!/usr/bin/env sh

set -eu

max_lines=600
violations=$(find lib config priv test -type f \( -name '*.ex' -o -name '*.exs' -o -name '*.eex' \) -print0 |
  xargs -0 wc -l |
  awk -v max="$max_lines" '$2 != "total" && $1 > max { print $1 " " $2 }')

if [ -n "$violations" ]; then
  echo "Source files must contain no more than ${max_lines} lines:"
  echo "$violations"
  exit 1
fi

echo "Source line limit OK (<= ${max_lines} lines)."
