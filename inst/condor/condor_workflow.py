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

Each job also independently derives split_seed = seed + (restart - 1) * 1000
(computed inside condor_fit.R, not passed as its own CLI argument) to draw
that restart's own internal_test resample via sample_internal_test() --
restart-dependent but not d/fraction-dependent, matching
estimate_dimensionality()/estimate_learning_curve() exactly. See
condor_fit.R's header comment for why this exists.
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
                  "fraction", "n_train", "n_fit", "n_internal_test"}


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
                       log, output, error, resources, initialdir,
                       queue_statement="queue\n"):
    """queue_statement is the literal trailing text of the submit file --
    either a plain "queue\\n" for a single job, or a multi-line
    "queue var1,var2,... from (\\n  ...\\n)\\n" block for many jobs sharing
    one submit description (see run_dimensionality_stage/
    run_learning_curve_stage).

    initialdir must be the (absolute) stage directory: it's where HTCondor
    transfers back any new output files a job creates (e.g. result_$(Process).csv
    written via a bare relative --output=... argument) -- without it, that
    default transfer targets whatever directory condor_submit happened to be
    run from, not the stage directory read_result_row() looks in afterwards."""
    content = f"""universe        = container
container_image = {container_image}

# Rscript lives inside the container image, not on the submit node -- without
# this, condor_submit stats `executable` locally before submission and fails
# with "Can't access executable file" even though the path is only ever
# resolved inside the container at runtime.
executable          = /usr/local/bin/Rscript
transfer_executable = False
arguments  = {arguments}

initialdir = {initialdir}

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
        if key in ("d", "restart", "epoch", "n_train", "n_fit", "n_internal_test"):
            row[key] = int(row[key])
    return row


def queue_from_block(varnames, rows):
    """Build a `queue var1,var2,... from (...)` statement -- one job per
    row, with $(var1) etc. substituted per-job in the submit file."""
    lines = [f"queue {','.join(varnames)} from ("]
    lines += [f"  {','.join(str(v) for v in row)}" for row in rows]
    lines.append(")\n")
    return "\n".join(lines)


def submit_jobs_with_retry(stage_dir, jobs, output_path_fn, build_and_submit, label,
                            batch_size=None, max_retries=5):
    """Submit `jobs`, verify every job's expected output file actually came
    back, and resubmit just the ones that didn't -- up to `max_retries`
    additional attempts -- before failing with a clear error naming exactly
    which ones never produced valid output.

    This exists because a real deployment of the sibling group-difference
    workflow hit HTCondor jobs that reported clean "Normal termination
    (return value 0)" yet whose output file came back empty or missing on
    the submit node -- consistent with many jobs finishing (and each trying
    to transfer output back) within the same narrow time window overloading
    something in the transfer path, not a bug in the per-job R script (an R
    error there would show up in a non-empty .err file and a nonzero return
    value, neither of which was observed). See
    vignette("condor_workflows_vignette") for the full writeup.

    `output_path_fn(job)` returns the expected output Path for a given job
    (this stage names results by Process index within a jobs list rather
    than a per-job filename column, unlike the other two workflows, hence a
    function instead of a fixed column index). `build_and_submit(jobs_subset)`
    must write a submit file for exactly those jobs and block until they
    finish (i.e. an ordinary write_submit_file() + submit_and_wait() call).

    `batch_size`, if set, splits `jobs` into sequential chunks submitted (and
    retried) one at a time instead of all at once -- capping how many jobs
    can possibly finish in the same narrow window in the first place, which
    directly reduces how often this failure mode is triggered rather than
    just cleaning up after it. Default `None` preserves the original
    single-submission behavior.
    """
    batches = [jobs] if not batch_size else [
        jobs[i:i + batch_size] for i in range(0, len(jobs), batch_size)
    ]

    for batch_num, batch in enumerate(batches, start=1):
        remaining = batch
        for attempt in range(1, max_retries + 2):
            build_and_submit(remaining)
            missing = [j for j in remaining
                       if not output_path_fn(j).exists() or output_path_fn(j).stat().st_size == 0]
            if not missing:
                break
            batch_note = f" (batch {batch_num}/{len(batches)})" if batch_size else ""
            print(f"[condor_workflow] {label}{batch_note}: {len(missing)} of "
                  f"{len(remaining)} output(s) missing/empty after attempt "
                  f"{attempt} -- retrying")
            remaining = missing
        else:
            sys.exit(
                f"{label}: {len(remaining)} output(s) still missing/empty after "
                f"{max_retries} retries. Check their .err files in {stage_dir}/ for what "
                "actually happened -- a clean, non-empty .out with an empty .err points "
                "to the file-transfer issue described above rather than a script error."
            )


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
                              norm_penalty, container_image, batch_size=None):
    dim_cfg = config.get("dimensionality") or {}
    dims = parse_dims(dim_cfg.get("dims", "1:8"))
    n_restarts = int(get_config(dim_cfg, "n_restarts", config, 10))
    best_d_norm_penalty = dim_cfg.get("best_d_norm_penalty")
    if best_d_norm_penalty is None:
        best_d_norm_penalty = norm_penalty

    # job_index (last field) names each job's output file (result_<job_index>.csv)
    # independently of Condor's own $(Process) number for that particular
    # submission -- required so that a retry submitting only a SUBSET of jobs
    # (see submit_jobs_with_retry()) doesn't reassign low Process numbers to
    # different jobs and overwrite already-good results with the same name.
    combos = [(d, restart) for d in dims for restart in range(1, n_restarts + 1)]
    jobs = [(d, restart, seed + (restart - 1) * 1000 + d, i)
            for i, (d, restart) in enumerate(combos)]

    stage_dir = work_dir / "stage1_dimensionality"
    stage_dir.mkdir(parents=True, exist_ok=True)

    fixed_args = (
        f"condor_fit.R --stage=dimensionality --triplet_data={data_path.name} "
        f"--output=result_$(job_index).csv --fraction=NA "
        f"--base_seed={seed} "
        f"--internal_test_frac={get_config(dim_cfg, 'internal_test_frac', config, 0.1)} "
        f"--max_epochs={get_config(dim_cfg, 'max_epochs', config, 50000)} "
        f"--tolerance={get_config(dim_cfg, 'tolerance', config, 1e-4)} "
        f"--tol_window={get_config(dim_cfg, 'tol_window', config, 10000)} "
        f"--device={get_config(dim_cfg, 'device', config, 'cpu')} "
        f"--geometry={geometry} --radius={radius} --norm_penalty={norm_penalty} "
        f"--d=$(d) --restart=$(restart) --random_state=$(random_state)"
    )

    def build_and_submit(jobs_subset):
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
            initialdir=str(stage_dir),
            queue_statement=queue_from_block(
                ["d", "restart", "random_state", "job_index"], jobs_subset
            ),
        )
        submit_and_wait(submit_path, stage_dir / "dim.log", "Stage 1 (dimensionality)")

    submit_jobs_with_retry(
        stage_dir, jobs, output_path_fn=lambda j: stage_dir / f"result_{j[3]}.csv",
        build_and_submit=build_and_submit, label="Stage 1 (dimensionality)",
        batch_size=batch_size,
    )

    results = [read_result_row(stage_dir / f"result_{i}.csv") for i in range(len(jobs))]
    summary, best_d = summarize_dimensionality(results, n_restarts, best_d_norm_penalty)

    write_csv(work_dir / "dimensionality_results.csv", results)
    write_csv(work_dir / "dimensionality_summary.csv", summary)
    print(f"[condor_workflow] Selected best_d = {best_d}")
    return best_d


def run_learning_curve_stage(work_dir, data_path, config, seed, best_d, norm_penalty,
                              container_image, batch_size=None):
    lc_cfg = config.get("learning_curve") or {}
    by = get_config(lc_cfg, "by", config, 0.1)
    n_restarts = int(get_config(lc_cfg, "n_restarts", config, 10))
    fractions = compute_fractions(by)

    # random_state matches estimate_learning_curve()'s own formula, keyed by
    # the fraction's 1-based index `i` in the grid (not restart-dependent on
    # its own). job_index is a separate, purely positional identity used
    # only to name each job's output file -- see run_dimensionality_stage()
    # for why this must be independent of Condor's own $(Process) number.
    jobs = []
    job_index = 0
    for i, frac in enumerate(fractions, start=1):
        for restart in range(1, n_restarts + 1):
            random_state = seed + (restart - 1) * 1000 + i
            jobs.append((frac, restart, random_state, job_index))
            job_index += 1

    stage_dir = work_dir / "stage2_learning_curve"
    stage_dir.mkdir(parents=True, exist_ok=True)

    fixed_args = (
        f"condor_fit.R --stage=learning_curve --triplet_data={data_path.name} "
        f"--output=result_$(job_index).csv --d={best_d} "
        f"--base_seed={seed} "
        f"--internal_test_frac={get_config(lc_cfg, 'internal_test_frac', config, 0.1)} "
        f"--max_epochs={get_config(lc_cfg, 'max_epochs', config, 50000)} "
        f"--tolerance={get_config(lc_cfg, 'tolerance', config, 1e-4)} "
        f"--tol_window={get_config(lc_cfg, 'tol_window', config, 10000)} "
        f"--device={get_config(lc_cfg, 'device', config, 'cpu')} "
        f"--geometry=euclidean --radius=1 --norm_penalty={norm_penalty} "
        f"--fraction=$(fraction) --restart=$(restart) --random_state=$(random_state)"
    )

    def build_and_submit(jobs_subset):
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
            initialdir=str(stage_dir),
            queue_statement=queue_from_block(
                ["fraction", "restart", "random_state", "job_index"], jobs_subset
            ),
        )
        submit_and_wait(submit_path, stage_dir / "lc.log", "Stage 2 (learning curve)")

    submit_jobs_with_retry(
        stage_dir, jobs, output_path_fn=lambda j: stage_dir / f"result_{j[3]}.csv",
        build_and_submit=build_and_submit, label="Stage 2 (learning curve)",
        batch_size=batch_size,
    )

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
        # internal_test_frac is required by condor_fit.R's arg parser for
        # every stage but is not used by stage=final (which relies on
        # run_group_embedding_from_list()'s own train/test handling).
        f"--internal_test_frac={get_config(ff_cfg, 'internal_test_frac', config, 0.1)} "
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
        initialdir=str(stage_dir),
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

    # Resolve to absolute paths up front: once a stage sets initialdir (see
    # write_submit_file()), HTCondor resolves every other relative path in
    # that submit file (log/output/error/transfer_input_files) against
    # initialdir rather than the directory condor_workflow.py was run from,
    # so anything that must still mean "relative to here" has to be made
    # absolute before it reaches write_submit_file().
    work_dir = Path(config.get("output_dir", "condor_output")).resolve()
    work_dir.mkdir(parents=True, exist_ok=True)
    args.triplet_data = args.triplet_data.resolve()

    seed         = int(config.get("seed", 1))
    geometry     = config.get("geometry", "euclidean")
    radius       = config.get("radius", 1)
    norm_penalty = config.get("norm_penalty", 0)

    condor_cfg = config.get("condor") or {}
    container_image = condor_cfg.get(
        "container_image",
        "docker://ghcr.io/knowledge-and-concepts-lab/triplettools:latest",
    )
    batch_size = condor_cfg.get("batch_size")

    print(f"[condor_workflow] geometry={geometry} norm_penalty={norm_penalty} "
          f"container_image={container_image}")

    best_d = run_dimensionality_stage(
        work_dir, args.triplet_data, config, seed, geometry, radius,
        norm_penalty, container_image, batch_size=batch_size,
    )
    run_learning_curve_stage(
        work_dir, args.triplet_data, config, seed, best_d, norm_penalty,
        container_image, batch_size=batch_size,
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
