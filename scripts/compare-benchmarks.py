#!/usr/bin/env python3
"""
Compare benchmark results from two runs.

Usage:
    python3 scripts/compare-benchmarks.py <baseline-dir> <current-dir>

Reads summary.tsv and metadata.json from each directory.
Reports per-scenario and overall changes in token usage.
"""

import json
import sys
from pathlib import Path


def load_run(results_dir):
    """Load metadata and summary from a benchmark run."""
    results_dir = Path(results_dir)

    meta_path = results_dir / "metadata.json"
    if meta_path.exists():
        with open(meta_path) as f:
            metadata = json.load(f)
    else:
        metadata = {"branch": "unknown", "commit": "unknown"}

    summary_path = results_dir / "summary.tsv"
    scenarios = {}
    if summary_path.exists():
        with open(summary_path) as f:
            header = f.readline().strip().split("\t")
            for line in f:
                parts = line.strip().split("\t")
                if len(parts) >= 6:
                    name = parts[0]
                    scenarios[name] = {
                        "input_tokens": int(parts[1]),
                        "output_tokens": int(parts[2]),
                        "cache_create": int(parts[3]),
                        "cache_read": int(parts[4]),
                        "total_context": int(parts[5]),
                    }

    return metadata, scenarios


def fmt(n):
    """Format number with commas."""
    return f"{n:,}"


def pct(old, new):
    """Format percentage change."""
    if old == 0:
        return "n/a"
    change = (new - old) / old * 100
    sign = "+" if change > 0 else ""
    return f"{sign}{change:.1f}%"


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)

    base_meta, base_scenarios = load_run(sys.argv[1])
    curr_meta, curr_scenarios = load_run(sys.argv[2])

    print(f"\n=== Benchmark Comparison ===\n")
    print(f"Baseline: {base_meta['branch']} @ {base_meta['commit']}")
    print(f"Current:  {curr_meta['branch']} @ {curr_meta['commit']}")
    print()

    # Per-scenario comparison (focus on total_context = input + cache_create + cache_read)
    all_scenarios = sorted(set(list(base_scenarios.keys()) + list(curr_scenarios.keys())))

    print(f"{'Scenario':<25} {'Baseline':>12} {'Current':>12} {'Change':>10}")
    print(f"{'-'*25} {'-'*12} {'-'*12} {'-'*10}")

    base_total = 0
    curr_total = 0

    for name in all_scenarios:
        b = base_scenarios.get(name, {}).get("total_context", 0)
        c = curr_scenarios.get(name, {}).get("total_context", 0)
        base_total += b
        curr_total += c
        print(f"{name:<25} {fmt(b):>12} {fmt(c):>12} {pct(b, c):>10}")

    print(f"{'-'*25} {'-'*12} {'-'*12} {'-'*10}")
    print(f"{'TOTAL':<25} {fmt(base_total):>12} {fmt(curr_total):>12} {pct(base_total, curr_total):>10}")

    # Breakdown by token type
    print(f"\n--- Cache-Read Tokens (primary cost driver) ---\n")
    print(f"{'Scenario':<25} {'Baseline':>12} {'Current':>12} {'Change':>10}")
    print(f"{'-'*25} {'-'*12} {'-'*12} {'-'*10}")

    base_cr_total = 0
    curr_cr_total = 0

    for name in all_scenarios:
        b = base_scenarios.get(name, {}).get("cache_read", 0)
        c = curr_scenarios.get(name, {}).get("cache_read", 0)
        base_cr_total += b
        curr_cr_total += c
        print(f"{name:<25} {fmt(b):>12} {fmt(c):>12} {pct(b, c):>10}")

    print(f"{'-'*25} {'-'*12} {'-'*12} {'-'*10}")
    print(f"{'TOTAL':<25} {fmt(base_cr_total):>12} {fmt(curr_cr_total):>12} {pct(base_cr_total, curr_cr_total):>10}")

    print(f"\n=== End Comparison ===\n")
    print("Key: total_context = input + cache_creation + cache_read tokens.")
    print("Cache-read tokens are the primary driver of usage-limit burn.")
    print("Lower numbers = better context discipline.")


if __name__ == "__main__":
    main()
