#!/usr/bin/env bash
# Agent context benchmark runner
#
# Runs standardized prompts and measures actual token usage.
# Results are saved for comparison across branches/commits.
#
# Usage:
#   ./scripts/run-benchmark.sh              # run with defaults
#   MODEL=opus ./scripts/run-benchmark.sh   # override model
#   MAX_BUDGET=0.50 ./scripts/run-benchmark.sh
#
# Comparison workflow:
#   git checkout main
#   ./scripts/run-benchmark.sh          # saves to results/<branch>-<timestamp>/
#   git checkout optimize-agent-context
#   ./scripts/run-benchmark.sh          # saves to results/<branch>-<timestamp>/
#   python3 scripts/compare-benchmarks.py results/main-* results/optimize-agent-context-*

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMPT_DIR="$SCRIPT_DIR/benchmark-prompts"

# Configuration
MODEL="${MODEL:-sonnet}"
MAX_BUDGET="${MAX_BUDGET:-1.00}"

# Identify current branch and commit
BRANCH=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)
COMMIT=$(git -C "$REPO_DIR" rev-parse --short HEAD)
RUN_ID="${BRANCH}-$(date +%Y%m%d-%H%M%S)"
RESULTS_DIR="$REPO_DIR/benchmark-results/$RUN_ID"
mkdir -p "$RESULTS_DIR"

cat <<INFO
=== Agent Context Benchmark ===
Branch:     $BRANCH
Commit:     $COMMIT
Model:      $MODEL
Max budget: \$$MAX_BUDGET per prompt
Results:    $RESULTS_DIR

This will run $(ls "$PROMPT_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ') prompts as read-only Claude sessions.
Each prompt consumes real tokens.

INFO

read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# Record run metadata
cat > "$RESULTS_DIR/metadata.json" <<METADATA
{
    "branch": "$BRANCH",
    "commit": "$COMMIT",
    "model": "$MODEL",
    "max_budget_usd": "$MAX_BUDGET",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
METADATA

# Summary accumulator
SUMMARY_FILE="$RESULTS_DIR/summary.tsv"
printf "scenario\tinput_tokens\toutput_tokens\tcache_create\tcache_read\ttotal_context\n" > "$SUMMARY_FILE"

run_prompt() {
    local name="$1"
    local prompt_file="$2"

    echo "--- Running: $name ---"

    local prompt
    prompt=$(<"$prompt_file")

    # Run read-only: only allow Read, Glob, Grep (no edits, no writes, no bash)
    local output_file="$RESULTS_DIR/$name.json"

    if claude -p "$prompt" \
        --model "$MODEL" \
        --max-budget-usd "$MAX_BUDGET" \
        --output-format json \
        --allowedTools "Read" "Glob" "Grep" \
        > "$output_file" 2>"$RESULTS_DIR/$name.stderr"; then
        echo "  completed"
    else
        echo "  completed (non-zero exit)"
    fi

    # Extract usage from JSON output
    local input_tokens output_tokens cache_create cache_read total_context
    if command -v python3 &>/dev/null; then
        read -r input_tokens output_tokens cache_create cache_read total_context < <(
            python3 -c "
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    u = data.get('usage')
    if not isinstance(u, dict):
        r = data.get('result')
        u = r.get('usage', {}) if isinstance(r, dict) else {}
    inp = u.get('input_tokens', 0)
    out = u.get('output_tokens', 0)
    cc = u.get('cache_creation_input_tokens', 0)
    cr = u.get('cache_read_input_tokens', 0)
    total = inp + cc + cr
    print(f'{inp}\t{out}\t{cc}\t{cr}\t{total}')
except Exception as e:
    print(f'0\t0\t0\t0\t0', file=sys.stdout)
    print(f'Parse error: {e}', file=sys.stderr)
" "$output_file" 2>>"$RESULTS_DIR/$name.stderr"
        )
    else
        input_tokens=0; output_tokens=0; cache_create=0; cache_read=0; total_context=0
    fi

    printf "  input=%s output=%s cache_create=%s cache_read=%s total_context=%s\n" \
        "$input_tokens" "$output_tokens" "$cache_create" "$cache_read" "$total_context"

    printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$name" "$input_tokens" "$output_tokens" "$cache_create" "$cache_read" "$total_context" \
        >> "$SUMMARY_FILE"
}

# Run each prompt
for prompt_file in "$PROMPT_DIR"/*.md; do
    name=$(basename "$prompt_file" .md)
    run_prompt "$name" "$prompt_file"
    echo ""
done

echo "=== Results ==="
echo ""
column -t -s$'\t' "$SUMMARY_FILE"
echo ""
echo "Saved to: $RESULTS_DIR"
echo ""
echo "To compare runs:"
echo "  python3 scripts/compare-benchmarks.py $RESULTS_DIR <other-results-dir>"
