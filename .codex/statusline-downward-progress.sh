#!/bin/sh
set -eu

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

summarize_checkboxes() {
    label="$1"
    file="$2"

    awk -v label="$label" '
        /^[[:space:]]*-[[:space:]]\[[ xX]\]/ {
            total += 1
            if ($0 ~ /\[[xX]\]/) {
                done += 1
            }
        }
        END {
            if (total == 0) {
                printf "%s 0/0", label
            } else {
                printf "%s %d/%d %.0f%%", label, done, total, (done * 100) / total
            }
        }
    ' "$file"
}

plans="$(summarize_checkboxes PLANS "$root/PLANS.md")"

printf "Downward %s\n" "$plans"
