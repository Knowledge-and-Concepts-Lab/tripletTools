#!/usr/bin/env python3
"""Standalone aggregation-only re-run for condor_recovery_sweep_workflow.py.

For when Stage 1 (the fit jobs) already completed -- stage1_fit/ is full of
result_rep*_gen*fit*.csv files -- but the run stopped, crashed, or was
interrupted before the final local aggregation step wrote results_long.csv /
error_matrix_mean.csv / error_matrix_sd.csv. Reruns just that step, against
the same params.yml used for the original submission, without resubmitting
or touching Condor at all.

Reconstructs the same `jobs` list run_fit_stage() would have built (same
(replicate, generating alpha, fitting alpha) -> output filename mapping,
since that naming is a pure function of `alphas` and `n_replicates` in the
config -- it doesn't depend on anything Condor assigned at submit time) and
hands it to the workflow's own aggregate_results(), so this script cannot
drift out of sync with how the real workflow names or aggregates results.

Usage:
    python3 condor_recovery_sweep_aggregate_only.py <params.yml>

<params.yml> must be the same config file used for the original
`condor_recovery_sweep_workflow.py <params.yml>` run (same alphas,
n_replicates, seed, output_dir).
"""
import argparse
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit(
        "PyYAML is required to read the config file. Install with:\n"
        "  pip install --user pyyaml"
    )

sys.path.insert(0, str(Path(__file__).resolve().parent))
import condor_recovery_sweep_workflow as rs  # noqa: E402


def rebuild_jobs(config):
    """Recreate run_fit_stage()'s jobs list from the config alone. Only the
    fields aggregate_results() actually reads (output_name, rep, gen_label,
    fit_label) need to be real; the transfer-related fields
    (triplets_src/name, gt_src/name, fit_seed) are irrelevant post-hoc since
    no job is being submitted, so they're left as None."""
    alphas = config["alphas"]
    n_replicates = int(rs.get_config(config, "n_replicates", 1))

    jobs = []
    for r in range(n_replicates):
        for gi, gen_alpha in enumerate(alphas):
            gen_label = rs.alpha_label(gen_alpha)
            for fi, fit_alpha in enumerate(alphas):
                fit_label = rs.alpha_label(fit_alpha)
                output_name = f"result_rep{r}_gen{gi}fit{fi}.csv"
                jobs.append((None, None, None, None, output_name, r, gen_label, fit_label, None))
    return jobs


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                      formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("params", type=Path,
                         help="Same YAML config file used for the original workflow run")
    args = parser.parse_args()

    if not args.params.exists():
        sys.exit(f"file not found: {args.params}")

    with open(args.params) as f:
        config = yaml.safe_load(f) or {}

    if "d" not in config:
        sys.exit("params.yml must set 'd' (the embedding dimensionality every fit uses).")
    if "alphas" not in config or not config["alphas"]:
        sys.exit("params.yml must set a non-empty 'alphas' list.")
    config["alphas"] = [float(a) for a in config["alphas"]]

    work_dir = Path(config.get("output_dir", "condor_recovery_sweep_output")).resolve()
    stage1_dir = work_dir / "stage1_fit"
    if not stage1_dir.is_dir():
        sys.exit(f"Stage 1 output directory not found: {stage1_dir}\n"
                  "Nothing to aggregate -- did the original run use a different output_dir?")

    jobs = rebuild_jobs(config)
    n_replicates = int(rs.get_config(config, "n_replicates", 1))
    print(f"[condor_recovery_sweep_aggregate_only] Aggregating {len(jobs)} expected fit results "
          f"({n_replicates} replicate(s) x {len(config['alphas'])} alphas) from {stage1_dir}")

    long_path, mean_path, sd_path = rs.aggregate_results(work_dir, stage1_dir, jobs, config["alphas"])

    print(f"[condor_recovery_sweep_aggregate_only] Done. Wrote {long_path}, "
          f"{mean_path}, and {sd_path}")


if __name__ == "__main__":
    main()
