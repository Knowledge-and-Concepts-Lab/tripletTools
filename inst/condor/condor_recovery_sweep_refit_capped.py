#!/usr/bin/env python3
"""Targeted re-fit of just the capped (non-converged) cells from a prior
condor_recovery_sweep_workflow.py run, at a higher max_epochs ceiling.

For when a post-hoc check (e.g. analyze_recovery_history.py, same
directory) shows a meaningful fraction of cells hit the epoch ceiling
without ever genuinely triggering early stopping -- comparing recovery
error between cells where some converged cleanly and others were simply
cut off is not a fair comparison, and it's usually a small minority of
cells (the slowest-converging ones) that need the larger budget, not the
whole sweep. This re-fits only those specific cells rather than
re-running everything.

Reuses the ORIGINAL simulated ground truth/triplets in stage0_simulate/ --
no new data is generated -- and re-derives each capped cell's exact
original fit_seed from its (replicate, generating alpha, fitting alpha)
position (the same deterministic formula condor_recovery_sweep_workflow.py
itself uses), so a refit cell traces the identical initialization and
train/test split as its original attempt, just given more epochs to
actually reach its stopping criterion, rather than being a fresh,
independently-seeded draw. That's what makes folding the result back into
the existing dataset a legitimate like-for-like comparison rather than a
different sample.

Which cells count as "capped" is inferred directly from the data, not
re-typed by hand: the original run's own max_epochs is simply the largest
`epoch` value appearing anywhere in results_long.csv (any fit that hit the
ceiling shows exactly that value, and none can exceed it), and any row at
or within one epoch of that value is treated as capped.

Does not touch stage1_fit/ or overwrite results_long.csv /
error_matrix_mean.csv / error_matrix_sd.csv -- new fits are written to a
new stage_refit/ directory, and a new results_long_refit.csv /
error_matrix_mean_refit.csv / error_matrix_sd_refit.csv are written
alongside the originals (every row from the original dataset, with just
the previously-capped ones replaced by their refit result), so the
original run's outputs are always still there for comparison/provenance.

Usage:
    python3 condor_recovery_sweep_refit_capped.py <params.yml> --max-epochs 200000

<params.yml> is the SAME config file used for the original
condor_recovery_sweep_workflow.py run (same alphas, n_replicates, seed,
output_dir, d, test_frac, tolerance, tol_window, device, condor settings)
-- only --max-epochs is overridden from the command line, since raising
that one setting is the whole point of this tool.
"""
import argparse
import csv
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


def find_capped_rows(results_long_path):
    """Returns (all_rows, capped_rows, old_max_epochs). `old_max_epochs` is
    inferred as the largest recorded epoch value -- the original run's own
    ceiling, whatever it was -- rather than asked for separately, so this
    can never drift out of sync with what the data actually shows."""
    with open(results_long_path, newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        sys.exit(f"{results_long_path} has no rows.")
    old_max_epochs = max(int(r["epoch"]) for r in rows)
    capped = [r for r in rows if int(r["epoch"]) >= old_max_epochs - 1]
    return rows, capped, old_max_epochs


def build_refit_jobs(capped_rows, alphas, seed):
    """Rebuilds the exact (triplets_src, triplets_name, gt_src, gt_name,
    output_name, rep, gen_label, fit_label, fit_seed) tuple
    run_fit_stage() would have built for each capped row, so these jobs
    point at the SAME already-simulated stage0_simulate/ files and use the
    SAME deterministic fit_seed as the cell's original attempt."""
    alpha_index = {rs.alpha_label(a): i for i, a in enumerate(alphas)}
    jobs = []
    for row in capped_rows:
        r = int(row["replicate"])
        gen_label = row["gen_alpha"]
        fit_label = row["fit_alpha"]
        gi = alpha_index[gen_label]
        fi = alpha_index[fit_label]
        rep_seed = seed + r * rs.REPLICATE_SEED_STRIDE
        fit_seed = rep_seed + gi * 100 + fi

        gt_name = f"ground_truth_rep{r}.csv"
        triplets_name = f"triplets_rep{r}_gen{gen_label}.csv"
        output_name = f"result_rep{r}_gen{gi}fit{fi}.csv"
        jobs.append((
            f"../stage0_simulate/{triplets_name}", triplets_name,
            f"../stage0_simulate/{gt_name}", gt_name,
            output_name, r, gen_label, fit_label, fit_seed,
        ))
    return jobs


def run_refit_stage(work_dir, jobs, config, max_epochs, resources, container_image, batch_size=None):
    stage_dir = work_dir / "stage_refit"
    stage_dir.mkdir(parents=True, exist_ok=True)

    d          = int(config["d"])
    tolerance  = rs.get_config(config, "tolerance", 1e-4)
    tol_window = rs.get_config(config, "tol_window", 3000)
    device     = rs.get_config(config, "device", "cpu")
    test_frac  = rs.get_config(config, "test_frac", 0.1)

    fixed_args = (
        "condor_recovery_fit.R --triplets=$(triplets_name) "
        "--ground_truth=$(gt_name) --replicate=$(rep) "
        "--gen_alpha=$(gen_label) --fit_alpha=$(fit_label) --output=$(output_name) "
        f"--d={d} --seed=$(fit_seed) --test_frac={test_frac} "
        f"--max_epochs={max_epochs} --tolerance={tolerance} --tol_window={tol_window} "
        f"--device={device}"
    )

    def build_and_submit(jobs_subset):
        submit_path = stage_dir / "refit.sub"
        rs.write_submit_file(
            submit_path,
            container_image=container_image,
            arguments=fixed_args,
            transfer_input_files=f"{rs.CONDOR_RECOVERY_FIT_R}, $(gt_src), $(triplets_src)",
            log=str(stage_dir / "refit.log"),
            output=str(stage_dir / "refit_$(Process).out"),
            error=str(stage_dir / "refit_$(Process).err"),
            resources=resources,
            initialdir=str(stage_dir),
            queue_statement=rs.queue_from_block(
                ["triplets_src", "triplets_name", "gt_src", "gt_name", "output_name",
                 "rep", "gen_label", "fit_label", "fit_seed"],
                jobs_subset,
            ),
        )
        rs.submit_and_wait(submit_path, stage_dir / "refit.log", "Capped-cell refit")

    print(f"[condor_recovery_sweep_refit] Queuing {len(jobs)} refit jobs at max_epochs={max_epochs}")
    rs.submit_jobs_with_retry(
        stage_dir, jobs, output_col=4,
        build_and_submit=build_and_submit,
        label="Capped-cell refit",
        batch_size=batch_size,
        extra_outputs=lambda j: [stage_dir / rs.history_output_name(j[4])],
    )
    return stage_dir


def merge_and_write(work_dir, all_rows, capped_rows, stage_refit_dir, alphas):
    """Replaces each originally-capped row with its refit result (read from
    stage_refit_dir) and writes results_long_refit.csv, plus
    error_matrix_mean_refit.csv / error_matrix_sd_refit.csv recomputed from
    the merged data -- every untouched row keeps its original value, only
    the previously-capped cells change."""
    alpha_index = {rs.alpha_label(a): i for i, a in enumerate(alphas)}
    refit_by_key = {}
    for row in capped_rows:
        gi = alpha_index[row["gen_alpha"]]
        fi = alpha_index[row["fit_alpha"]]
        output_name = f"result_rep{row['replicate']}_gen{gi}fit{fi}.csv"
        path = stage_refit_dir / output_name
        if not path.exists():
            sys.exit(f"Expected refit output missing: {path}. Check stage_refit/refit_*.err.")
        with open(path, newline="") as f:
            new_row = next(csv.DictReader(f))
        refit_by_key[(row["replicate"], row["gen_alpha"], row["fit_alpha"])] = new_row

    merged = []
    n_replaced = 0
    for row in all_rows:
        key = (row["replicate"], row["gen_alpha"], row["fit_alpha"])
        if key in refit_by_key:
            merged.append(refit_by_key[key])
            n_replaced += 1
        else:
            merged.append(row)

    long_path = work_dir / "results_long_refit.csv"
    with open(long_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["replicate", "gen_alpha", "fit_alpha",
                                                "recovery_error", "loss", "epoch"])
        writer.writeheader()
        writer.writerows(merged)

    errors_by_pair = {}
    for row in merged:
        key = (row["gen_alpha"], row["fit_alpha"])
        errors_by_pair.setdefault(key, []).append(float(row["recovery_error"]))

    labels = [rs.alpha_label(a) for a in alphas]

    def write_matrix(path, stat_index):
        with open(path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow([""] + [f"fit_{lbl}" for lbl in labels])
            for gen_lbl in labels:
                row_out = []
                for fit_lbl in labels:
                    values = errors_by_pair.get((gen_lbl, fit_lbl))
                    row_out.append(rs._mean_sd(values)[stat_index] if values else "")
                writer.writerow([f"gen_{gen_lbl}"] + row_out)

    mean_path = work_dir / "error_matrix_mean_refit.csv"
    sd_path = work_dir / "error_matrix_sd_refit.csv"
    write_matrix(mean_path, 0)
    write_matrix(sd_path, 1)

    return long_path, mean_path, sd_path, n_replaced


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                      formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("params", type=Path,
                         help="Same YAML config file used for the original workflow run")
    parser.add_argument("--max-epochs", type=int, required=True,
                         help="New, raised epoch ceiling for just the capped cells")
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
    seed = int(config.get("seed", 1))

    work_dir = Path(config.get("output_dir", "condor_recovery_sweep_output")).resolve()
    results_long_path = work_dir / "results_long.csv"
    if not results_long_path.exists():
        sys.exit(f"{results_long_path} not found -- did the original run finish and aggregate?")
    stage0_dir = work_dir / "stage0_simulate"
    if not stage0_dir.is_dir():
        sys.exit(f"{stage0_dir} not found -- this tool reuses the original run's simulated "
                  "ground truth/triplets and cannot regenerate them.")

    all_rows, capped_rows, old_max_epochs = find_capped_rows(results_long_path)
    print(f"[condor_recovery_sweep_refit] {len(all_rows)} total rows; "
          f"{len(capped_rows)} capped at the original ceiling (epoch>={old_max_epochs - 1}, "
          f"max_epochs was {old_max_epochs})")
    if not capped_rows:
        sys.exit("No capped rows found -- nothing to refit.")
    if args.max_epochs <= old_max_epochs:
        sys.exit(f"--max-epochs ({args.max_epochs}) must exceed the original ceiling "
                  f"({old_max_epochs}), or this would just reproduce the same capped result.")

    jobs = build_refit_jobs(capped_rows, config["alphas"], seed)

    condor_cfg = config.get("condor") or {}
    container_image = condor_cfg.get(
        "container_image",
        "docker://ghcr.io/knowledge-and-concepts-lab/triplettools:latest",
    )
    resources = condor_cfg.get("resources") or {}
    batch_size = condor_cfg.get("batch_size")

    stage_refit_dir = run_refit_stage(work_dir, jobs, config, args.max_epochs,
                                       resources, container_image, batch_size)
    long_path, mean_path, sd_path, n_replaced = merge_and_write(
        work_dir, all_rows, capped_rows, stage_refit_dir, config["alphas"])

    manifest = [
        f"Run finished:        {__import__('datetime').datetime.utcnow().isoformat()}Z",
        f"source config:       {args.params.resolve()}",
        f"original max_epochs: {old_max_epochs}",
        f"refit max_epochs:    {args.max_epochs}",
        f"rows refit:          {n_replaced} / {len(all_rows)}",
        f"results_long_refit:  {long_path}",
        f"error_matrix_mean_refit: {mean_path}",
        f"error_matrix_sd_refit:   {sd_path}",
    ]
    (work_dir / "refit_manifest.txt").write_text("\n".join(manifest) + "\n")

    print(f"[condor_recovery_sweep_refit] Done. {n_replaced} rows refit and merged into "
          f"{long_path}, {mean_path}, {sd_path}")


if __name__ == "__main__":
    main()
