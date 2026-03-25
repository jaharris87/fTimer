#!/usr/bin/env bash
# Context-load analysis for agent workflows
#
# Measures total lines (proxy for tokens) an agent would load
# for common task scenarios under the current repo structure.
#
# Usage: ./scripts/context-load-analysis.sh [baseline|current]
#   baseline - measure against main branch
#   current  - measure against working tree (default)
#
# Scenarios modeled:
#   1. Implement issue (coding task) — auto-loaded only
#   2. Open PR — auto-loaded + workflow docs
#   3. Fallback manual review — auto-loaded + review prompt
#   4. Findings disposition — auto-loaded + workflow docs
#   5. Review monitoring — auto-loaded + workflow docs
#   6. Full workflow in one session (worst case)
#
# For each scenario, we count lines in the files an agent would
# load if it followed the documented working rules.
# Source files and test files are task-dependent and not measured.

set -euo pipefail

MODE="${1:-current}"

count_lines() {
    local file="$1"
    if [ "$MODE" = "baseline" ]; then
        git show "main:$file" 2>/dev/null | wc -l | tr -d ' '
    else
        wc -l < "$file" 2>/dev/null | tr -d ' '
    fi
}

file_exists() {
    local file="$1"
    if [ "$MODE" = "baseline" ]; then
        git show "main:$file" &>/dev/null
    else
        [ -f "$file" ]
    fi
}

# Print a scenario table and accumulate total
# Args: scenario_name file1 file2 ...
scenario() {
    local name="$1"
    shift
    local total=0
    printf "\n--- Scenario: %s ---\n" "$name"
    printf "  %-50s %6s\n" "File" "Lines"
    printf "  %-50s %6s\n" "----" "-----"
    for file in "$@"; do
        if file_exists "$file"; then
            local lines
            lines=$(count_lines "$file")
            printf "  %-50s %6d\n" "$file" "$lines"
            total=$((total + lines))
        else
            printf "  %-50s %6s\n" "$file" "(n/a)"
        fi
    done
    printf "  %-50s %6d\n" "TOTAL" "$total"
}

printf "\n=== Context-Load Analysis (mode: %s) ===\n" "$MODE"

printf "\nAuto-loaded on every session (unavoidable):\n"
auto_total=0
for f in CLAUDE.md AGENTS.md; do
    if file_exists "$f"; then
        lines=$(count_lines "$f")
        printf "  %-50s %6d\n" "$f" "$lines"
        auto_total=$((auto_total + lines))
    fi
done
printf "  %-50s %6d\n" "Auto-load subtotal" "$auto_total"

# Scenario 1: Implement issue
# Agent reads: auto-loaded files + touched source + touched tests
# Does NOT need: maintainer.md, semantics.md, design.md, README
scenario "Implement issue (coding task, doc overhead only)" \
    CLAUDE.md

# Scenario 2: Open PR
if file_exists "docs/workflows/pr-open.md"; then
    scenario "Open PR" \
        CLAUDE.md \
        docs/workflows/pr-open.md
else
    scenario "Open PR" \
        CLAUDE.md \
        docs/maintainer.md
fi

# Scenario 3: Fallback manual review
scenario "Fallback manual review (software)" \
    CLAUDE.md \
    .github/prompts/detailed/software-review.md

# Scenario 4: Findings disposition
if file_exists "docs/workflows/findings-disposition.md"; then
    scenario "Findings disposition" \
        CLAUDE.md \
        docs/workflows/findings-disposition.md
else
    scenario "Findings disposition" \
        CLAUDE.md \
        docs/maintainer.md
fi

# Scenario 5: Review monitoring
if file_exists "docs/workflows/review-monitoring.md"; then
    scenario "Review monitoring" \
        CLAUDE.md \
        docs/workflows/review-monitoring.md
else
    scenario "Review monitoring" \
        CLAUDE.md \
        docs/maintainer.md
fi

# Scenario 6: Full workflow in one session (worst case)
if file_exists "docs/workflows/pr-open.md"; then
    scenario "Full workflow (one session, worst case)" \
        CLAUDE.md \
        docs/workflows/pr-open.md \
        docs/workflows/review-monitoring.md \
        docs/workflows/findings-disposition.md \
        .github/prompts/detailed/software-review.md
else
    scenario "Full workflow (one session, worst case)" \
        CLAUDE.md \
        docs/maintainer.md \
        .github/prompts/detailed/software-review.md
fi

printf "\n=== Notes ===\n"
printf "\n"
printf "Line counts are a proxy for token load.\n"
printf "Source/test files are task-dependent and not included.\n"
printf "Lower totals = less context burn per scenario.\n"
printf "Compare: ./scripts/context-load-analysis.sh baseline\n"
printf "    vs:  ./scripts/context-load-analysis.sh current\n"
