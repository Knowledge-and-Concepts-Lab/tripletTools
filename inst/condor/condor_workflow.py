#!/usr/bin/env python3
"""tripletTools Condor workflow driver (Python orchestrator).

Runs, on an HTCondor cluster, in order:
  1. Dimensionality search: one Condor job per (dimension, restart) pair.
  2. Learning curve at the selected best_d: one job per (fraction, restart).
  3. Final embedding: a single job, fit on the full dataset at best_d.

Every job runs condor_fit.R (in this same directory) inside the
tripletTools container image via HTCondor's container universe -- no R
installation is needed on the submit node, only Python and this script.

Usage:
    python3 condor_workflow.py <triplet_data.csv> <params.yml>

<triplet_data.csv> must be a combined CSV in the format get.combined()
reads (one row per triplet judgment, with a worker_id column). See
inst/extdata/icon_all_triplets.csv for an example.

<params.yml> follows params_template.yml in this same directory.

random_state derivation matches estimate_dimensionality()/
estimate_learning_curve() exactly, so results are directly comparable to
(and, given the same seed, numerically identical to) a local, non-Condor
run of those functions:
    dimensionality: random_state = seed + (restart - 1) * 1000 + d
    learning_curve: random_state = seed + (restart - 1) * 1000 + i
        where i is the 1-based index of the fraction in the sorted,
        deduplicated fraction grid (not the fraction's value).
"""
import argparse
import csv
import math
import re
import statistics
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit(
        "PyYAML is required to read the config file. Install with:\n"
        "  pip install --user pyyaml"
    )

SCRIPT_DIR = Path(__file__).resolve().parent
CONDOR_FIT_R = SCRIPT_DIR / "condor_fit.R"

NUMERIC_FIELDS = {"d", "restart", "loss", "accuracy", "epoch", "norm_ratio",
                  "fraction", "n_train"}


# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------

def parse_dims(spec):
    """Accept a YAML list (dims: [1, 2, 3]) or an R-style range string
    (dims: "1:8"), matching condor_helpers.R's parse_dims() convention."""
    if isinstance(spec, str):
        m = re.match(r"^\s*(-?\d+)\s*:\s*(-?\d+)\s*$", spec)
        if m:
            a, b = int(m.group(1)), int(m.group(2))
            return list(range(a, b + 1)) if a <= b else list(range(a, b - 1, -1))
        return [int(spec.strip())]
    return [int(x) for x in spec]


def compute_fractions(by):
    """Reproduce estimate_learning_curve()'s exact fraction grid."""
    n_steps = math.ceil(round(1 / by, 8))
    fractions = [round((i + 1) * by, 8) for i in range(n_steps)]
    fractions = [1.0 if f > 1 else f for f in fractions]
    seen, out = set(), []
    for f in fractions:
        if f not in seen:
            seen.add(f)
            out.append(f)
    return out


def get_config(stage_cfg, field, config, default=None):
    """Stage override > config['defaults'] > default, matching
    condor_helpers.R's get_config()."""
    if stage_cfg.get(field) is not None:
        return stage_cfg[field]
    defaults = config.get("defaults") or {}
    if defaults.get(field) is not None:
        return defaults[field]
    return default


def resources_config(stage_cfg, config):
    return stage_cfg.get("resources") or (config.get("defaults") or {}).get("resources") or {}


def condor_arg(value):
    """Render a Python value as a --key=value token; None becomes the
    literal string condor_fit.R treats as "not applicable"."""
    if value is None:
        return "NA"
    return str(value)


# ---------------------------------------------------------------------------
# Submit-file generation and job execution
# ---------------------------------------------------------------------------

def write_submit_file(path, *, container_image, arguments, transfer_input_files,
                       log, output, error, resources, queue_statement="queue\n"):
    """queue_statement is the literal trailing text of the submit file --
    either a plain "queue\\n" for a single job, or a multi-line
    "queue var1,var2,... from (\\n  ...\\n)\\n" block for many jobs sharing
    one submit description (see run_dimensionality_stage/
    run_learning_curve_stage)."""
    content = f"""universe        = container
container_image = {container_image}

executable = /usr/local/bin/Rscript
arguments  = {arguments}

transfer_input_files    = {transfer_input_files}
should_transfer_files   = YES
when_to_transfer_output = ON_EXIT

request_cpus   = {resources.get("request_cpus", 1)}
request_memory = {resources.get("request_memory", "4GB")}
request_disk   = {resources.get("request_disk", "8GB")}

log    = {log}
output = {output}
error  = {error}

{queue_statement}"""
    path.write_text(content)


def submit_and_wait(submit_path, log_path, label):
    print(f"[condor_workflow] Submitting {label} ({submit_path.name})...")
    result = subprocess.run(["condor_submit", str(submit_path)],
                             capture_output=True, text=True)
    print(result.stdout.strip())
    if result.returncode != 0:
        sys.exit(f"condor_submit failed for {label}:\n{result.stderr}")

    print(f"[condor_workflow] Waiting for {label} to finish "
          f"(condor_wait {log_path})...")
    wait = subprocess.run(["condor_wait", str(log_path)])
    if wait.returncode != 0:
        sys.exit(
            f"condor_wait exited with status {wait.returncode} for {label}. "
            f"Check {log_path} and the corresponding .out/.err files for "
            "held or failed jobs (condor_q -hold, condor_q -better-analyze)."
        )


def read_result_row(path):
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    if len(rows) != 1:
        raise ValueError(f"{path} does not contain exactly one result row")
    row = rows[0]
    for key in NUMERIC_FIELDS & row.keys():
        row[key] = float(row[key])
        if key in ("d", "restart", "epoch", "n_train"):
            row[key] = int(row[key])
    return row


def queue_from_block(varnames, rows):
    """Build a `queue var1,var2,... from (...)` statement -- one job per
    row, with $(var1) etc. substituted per-job in the submit file."""
    lines = [f"queue {','.join(varnames)} from ("]
    lines += [f"  {','.join(str(v) for v in row)}" for row in rows]
    lines.append(")\n")
    return "\n".join(lines)


def write_csv(path, rows):
    if not rows:
        path.write_text("")
        return
    fieldnames = list(rows[0].keys())
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


# ---------------------------------------------------------------------------
# Aggregation (ports of summarize_dimensionality()/summarize_learning_curve())
# ---------------------------------------------------------------------------

def summarize_dimensionality(results, n_restarts, best_d_norm_penalty):
    dims = sorted({r["d"] for r in results})
    summary = []
    for d in dims:
        sub = [r for r in results if r["d"] == d]
        losses      = [r["loss"] for r in sub]
        accs        = [r["accuracy"] for r in sub]
        norm_ratios = [r["norm_ratio"] for r in sub]
        summary.append({
            "d": d,
            "mean_loss": statistics.fmean(losses),
            "min_loss": min(losses),
            "sd_loss": statistics.stdev(losses) if len(losses) > 1 else "",
            "mean_accuracy": statistics.fmean(accs),
            "sd_accuracy": statistics.stdev(accs) if len(accs) > 1 else "",
            "mean_norm_ratio": statistics.fmean(norm_ratios),
            "max_norm_ratio": max(norm_ratios),
        })

    for row in summary:
        row["penalized_loss"] = row["mean_loss"] + \
            best_d_norm_penalty * (row["max_norm_ratio"] - 1)

    best_idx = min(range(len(summary)), key=lambda i: summary[i]["penalized_loss"])
    best_sd  = summary[best_idx]["sd_loss"] or 0.0
    best_se  = best_sd / math.sqrt(n_restarts)
    threshold = summary[best_idx]["penalized_loss"] + best_se
    eligible  = [row["d"] for row in summary if row["penalized_loss"] <= threshold]
    best_d    = min(eligible)
    for row in summary:
        row["best_d"] = (row["d"] == best_d)

    return summary, best_d


def summarize_learning_curve(results):
    fractions = sorted({r["fraction"] for r in results})
    summary = []
    for frac in fractions:
        sub = [r for r in results if r["fraction"] == frac]
        losses      = [r["loss"] for r in sub]
        accs        = [r["accuracy"] for r in sub]
        norm_ratios = [r["norm_ratio"] for r in sub]
        summary.append({
            "fraction": frac,
            "n_train": sub[0]["n_train"],
            "mean_loss": statistics.fmean(losses),
            "sd_loss": statistics.stdev(losses) if len(losses) > 1 else "",
            "mean_accuracy": statistics.fmean(accs),
            "sd_accuracy": statistics.stdev(accs) if len(accs) > 1 else "",
            "mean_norm_ratio": statistics.fmean(norm_ratios),
            "max_norm_ratio": max(norm_ratios),
        })
    return summary


# ---------------------------------------------------------------------------
# Stages
# ---------------------------------------------------------------------------

def run_dimensionality_stage(work_dir, data_path, config, seed, geometry, radius,
                              norm_penalty, container_image):
    dim_cfg = config.get("dimensionality") or {}
    dims = parse_dims(dim_cfg.get("dims", "1:8"))
    n_restarts = int(get_config(dim_cfg, "n_restarts", config, 10))
    best_d_norm_penalty = dim_cfg.get("best_d_norm_penalty")
    if best_d_norm_penalty is None:
        best_d_norm_penalty = norm_penalty

    jobs = [(d, restart, seed + (restart - 1) * 1000 + d)
            for d in dims for restart in range(1, n_restarts + 1)]

    stage_dir = work_dir / "stage1_dimensionality"
    stage_dir.mkdir(parents=True, exist_ok=True)

    # One queue line per job: Process $(Process) (0-based) maps to jobs[Process].
    fixed_args = (
        f"condor_fit.R --stage=dimensionality --triplet_data={data_path.name} "
        f"--output=result_$(Process).csv --fraction=NA "
        f"--base_seed={seed} --max_epochs={get_config(dim_cfg, 'max_epochs', config, 50000)} "
        f"--tolerance={get_config(dim_cfg, 'tolerance', config, 1e-4)} "
        f"--tol_window={get_config(dim_cfg, 'tol_window', config, 10000)} "
        f"--device={get_config(dim_cfg, 'device', config, 'cpu')} "
        f"--geometry={geometry} --radius={radius} --norm_penalty={norm_penalty} "
        f"--d=$(d) --restart=$(restart) --random_state=$(random_state)"
    )

    submit_path = stage_dir / "dim.sub"
    write_submit_file(
        submit_path,
        container_image=container_image,
        arguments=fixed_args,
        transfer_input_files=f"{CONDOR_FIT_R}, {data_path}",
        log=str(stage_dir / "dim.log"),
        output=str(stage_dir / "dim_$(Process).out"),
        error=str(stage_dir / "dim_$(Process).err"),
        resources=resources_config(dim_cfg, config),
        queue_statement=queue_from_block(["d", "restart", "random_state"], jobs),
    )

    submit_and_wait(submit_path, stage_dir / "dim.log", "Stage 1 (dimensionality)")

    results = [read_result_row(stage_dir / f"result_{i}.csv") for i in range(len(jobs))]
    summary, best_d = summarize_dimensionality(results, n_restarts, best_d_norm_penalty)

    write_csv(work_dir / "dimensionality_results.csv", results)
    write_csv(work_dir / "dimensionality_summary.csv", summary)
    print(f"[condor_workflow] Selected best_d = {best_d}")
    return best_d


def run_learning_curve_stage(work_dir, data_path, config, seed, best_d, norm_penalty,
                              container_image):
    lc_cfg = config.get("learning_curve") or {}
    by = get_config(lc_cfg, "by", config, 0.1)
    n_restarts = int(get_config(lc_cfg, "n_restarts", config, 10))
    fractions = compute_fractions(by)

    jobs = [(frac, restart, seed + (restart - 1) * 1000 + i)
            for i, frac in enumerate(fractions, start=1)
            for restart in range(1, n_restarts + 1)]

    stage_dir = work_dir / "stage2_learning_curve"
    stage_dir.mkdir(parents=True, exist_ok=True)

    fixed_args = (
        f"condor_fit.R --stage=learning_curve --triplet_data={data_path.name} "
        f"--output=result_$(Process).csv --d={best_d} "
        f"--base_seed={seed} --max_epochs={get_config(lc_cfg, 'max_epochs', config, 50000)} "
        f"--tolerance={get_config(lc_cfg, 'tolerance', config, 1e-4)} "
        f"--tol_window={get_config(lc_cfg, 'tol_window', config, 10000)} "
        f"--device={get_config(lc_cfg, 'device', config, 'cpu')} "
        f"--geometry=euclidean --radius=1 --norm_penalty={norm_penalty} "
        f"--fraction=$(fraction) --restart=$(restart) --random_state=$(random_state)"
    )

    submit_path = stage_dir / "lc.sub"
    write_submit_file(
        submit_path,
        container_image=container_image,
        arguments=fixed_args,
        transfer_input_files=f"{CONDOR_FIT_R}, {data_path}",
        log=str(stage_dir / "lc.log"),
        output=str(stage_dir / "lc_$(Process).out"),
        error=str(stage_dir / "lc_$(Process).err"),
        resources=resources_config(lc_cfg, config),
        queue_statement=queue_from_block(["fraction", "restart", "random_state"], jobs),
    )

    submit_and_wait(submit_path, stage_dir / "lc.log", "Stage 2 (learning curve)")

    results = [read_result_row(stage_dir / f"result_{i}.csv") for i in range(len(jobs))]
    summary = summarize_learning_curve(results)

    write_csv(work_dir / "learning_curve_results.csv", results)
    write_csv(work_dir / "learning_curve_summary.csv", summary)


def run_final_stage(work_dir, data_path, config, seed, best_d, geometry, radius,
                     norm_penalty, container_image):
    ff_cfg = config.get("final_fit") or {}
    stage_dir = work_dir / "stage3_final"
    stage_dir.mkdir(parents=True, exist_ok=True)

    arguments = (
        f"condor_fit.R --stage=final --triplet_data={data_path.name} "
        f"--output=embedding.csv --d={best_d} --fraction=NA --restart=1 "
        f"--base_seed={seed} --random_state={seed} "
        f"--max_epochs={get_config(ff_cfg, 'max_epochs', config, 50000)} "
        f"--tolerance={get_config(ff_cfg, 'tolerance', config, 1e-4)} "
        f"--tol_window={get_config(ff_cfg, 'tol_window', config, 10000)} "
        f"--device={get_config(ff_cfg, 'device', config, 'cpu')} "
        f"--geometry={geometry} --radius={radius} --norm_penalty={norm_penalty}"
    )

    submit_path = stage_dir / "final.sub"
    write_submit_file(
        submit_path,
        container_image=container_image,
        arguments=arguments,
        transfer_input_files=f"{CONDOR_FIT_R}, {data_path}",
        log=str(stage_dir / "final.log"),
        output=str(stage_dir / "final.out"),
        error=str(stage_dir / "final.err"),
        resources=resources_config(ff_cfg, config),
    )

    submit_and_wait(submit_path, stage_dir / "final.log", "Stage 3 (final embedding)")

    (work_dir / "best_embedding.csv").write_text(
        (stage_dir / "embedding.csv").read_text())
    (work_dir / "best_embedding_history.csv").write_text(
        (stage_dir / "embedding_history.csv").read_text())


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                      formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("triplet_data", type=Path,
                         help="Combined CSV in the format get.combined() reads")
    parser.add_argument("params", type=Path, help="YAML config file")
    args = parser.parse_args()

    if not args.triplet_data.exists():
        sys.exit(f"triplet_data file not found: {args.triplet_data}")
    if not args.params.exists():
        sys.exit(f"params file not found: {args.params}")

    with open(args.params) as f:
        config = yaml.safe_load(f) or {}

    work_dir = Path(config.get("output_dir", "condor_output"))
    work_dir.mkdir(parents=True, exist_ok=True)

    seed         = int(config.get("seed", 1))
    geometry     = config.get("geometry", "euclidean")
    radius       = config.get("radius", 1)
    norm_penalty = config.get("norm_penalty", 0)

    condor_cfg = config.get("condor") or {}
    container_image = condor_cfg.get(
        "container_image",
        "docker://ghcr.io/knowledge-and-concepts-lab/triplettools:latest",
    )

    print(f"[condor_workflow] geometry={geometry} norm_penalty={norm_penalty} "
          f"container_image={container_image}")

    best_d = run_dimensionality_stage(
        work_dir, args.triplet_data, config, seed, geometry, radius,
        norm_penalty, container_image,
    )
    run_learning_curve_stage(
        work_dir, args.triplet_data, config, seed, best_d, norm_penalty,
        container_image,
    )
    run_final_stage(
        work_dir, args.triplet_data, config, seed, best_d, geometry, radius,
        norm_penalty, container_image,
    )

    manifest = [
        f"Run finished:   {__import__('datetime').datetime.utcnow().isoformat()}Z",
        f"triplet_data:   {args.triplet_data.resolve()}",
        f"config:         {args.params.resolve()}",
        f"geometry:       {geometry}",
        f"norm_penalty:   {norm_penalty}",
        f"best_d:         {best_d}",
        f"container_image:{container_image}",
    ]
    (work_dir / "run_manifest.txt").write_text("\n".join(manifest) + "\n")

    print(f"[condor_workflow] Done. Outputs written to {work_dir}/")


if __name__ == "__main__":
    main()
