#!/usr/bin/env python3
"""Offline early-stopping-rule replay for the choice-model recovery-sweep
Condor workflow (condor_recovery_sweep_workflow.py, same directory).

condor_recovery_fit.R saves a "<result>_history.csv" alongside every
fit's single-row result, holding the full per-score_every-epoch test-loss
trajectory recorded by _fit_offline() -- whether that fit converged
naturally or ran to max_epochs. This script replays the *_fit_offline*
early-stopping comparison (`penalized_loss < current_lowest - tolerance`,
patience reset on that condition, stop when the patience counter exceeds
tol_window) against those saved trajectories under different candidate
(tolerance, tol_window) settings, entirely offline -- no Condor jobs, no
rerunning any fit.

This is for answering "would a different tolerance/tol_window have let the
still-capped fits converge sooner, and at what loss cost" using data
that's already been paid for, before deciding whether another sweep is
worth running.

Usage:
    python3 analyze_recovery_history.py <stage1_fit_dir> \
        [--tolerances 1e-3,5e-3,1e-2] [--tol-windows 3000,6000] \
        [--max-epochs 300000]

Reports, for each (tolerance, tol_window) candidate: the distribution of
simulated stop epochs across every history file found, how many would
still reach the end of the recorded trajectory (i.e. still "capped" even
under that candidate -- true early stopping was never triggered), and the
mean loss cost of stopping there vs. the best loss ever seen in the full
recorded trajectory (positive = stopping early gave up some accuracy).
"""
import argparse
import csv
import statistics
import sys
from pathlib import Path


def load_history(path):
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    return [
        {"epoch": int(r["epoch"]), "test_loss": float(r["test_loss"])}
        for r in rows
    ]


def simulate_early_stop(history, tolerance, tol_window):
    """Replays _fit_offline's counter logic against a recorded trajectory.
    Returns (stop_epoch, loss_at_stop, best_loss_ever, hit_end_of_history).

    `score_every` here is inferred from the recorded epoch spacing (the
    gap between consecutive history rows), matching how the real run
    scored -- this replay can only evaluate the rule at the resolution the
    data was actually sampled at.
    """
    if len(history) < 2:
        h = history[0]
        return h["epoch"], h["test_loss"], h["test_loss"], True

    score_every = history[1]["epoch"] - history[0]["epoch"]
    best_loss = history[0]["test_loss"]
    best_epoch = history[0]["epoch"]
    counter = 0
    for row in history[1:]:
        if row["test_loss"] < best_loss - tolerance:
            best_loss = row["test_loss"]
            best_epoch = row["epoch"]
            counter = 0
        else:
            counter += score_every
        if counter > tol_window:
            return best_epoch, best_loss, min(r["test_loss"] for r in history), False
    return best_epoch, best_loss, min(r["test_loss"] for r in history), True


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                      formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("stage1_dir", type=Path,
                         help="Directory holding result_*_history.csv files (stage1_fit/)")
    parser.add_argument("--tolerances", default="1e-3,2e-3,5e-3,1e-2",
                         help="Comma-separated candidate tolerance values")
    parser.add_argument("--tol-windows", default="3000",
                         help="Comma-separated candidate tol_window values")
    args = parser.parse_args()

    history_files = sorted(args.stage1_dir.glob("result_*_history.csv"))
    if not history_files:
        sys.exit(f"No *_history.csv files found in {args.stage1_dir}")

    print(f"Loading {len(history_files)} history files from {args.stage1_dir}...")
    histories = [load_history(p) for p in history_files]

    tolerances = [float(t) for t in args.tolerances.split(",")]
    tol_windows = [int(t) for t in args.tol_windows.split(",")]

    recorded_max_epoch = max(h[-1]["epoch"] for h in histories)
    print(f"(recorded trajectories run up to epoch {recorded_max_epoch} at the longest)\n")

    header = f"{'tolerance':>10}  {'tol_window':>10}  {'n':>5}  {'median_stop':>12}  {'p95_stop':>9}  {'still_uncapped_at_end':>22}  {'mean_loss_cost':>15}"
    print(header)
    print("-" * len(header))
    for tol in tolerances:
        for tw in tol_windows:
            stops, costs, hit_end = [], [], 0
            for h in histories:
                stop_epoch, loss_at_stop, best_ever, reached_end = simulate_early_stop(h, tol, tw)
                stops.append(stop_epoch)
                costs.append(loss_at_stop - best_ever)
                if reached_end:
                    hit_end += 1
            stops_sorted = sorted(stops)
            p95 = stops_sorted[int(0.95 * (len(stops_sorted) - 1))]
            print(f"{tol:>10.4g}  {tw:>10d}  {len(stops):>5d}  {statistics.median(stops):>12.0f}  "
                  f"{p95:>9.0f}  {hit_end:>13d} ({100*hit_end/len(stops):>4.1f}%)  "
                  f"{statistics.mean(costs):>15.6f}")

    print("\nColumns: median/p95 simulated stop epoch under that (tolerance, tol_window); "
          "'still_uncapped_at_end' = how many fits never triggered this rule within the "
          "recorded trajectory (would need either a bigger tolerance/tol_window or a bigger "
          "max_epochs, not just a faster rule); mean_loss_cost = average (loss at simulated "
          "stop) - (best loss ever seen in the full recorded trajectory) -- near zero means "
          "stopping there cost essentially nothing.")


if __name__ == "__main__":
    main()
