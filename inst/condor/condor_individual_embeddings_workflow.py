#!/usr/bin/env python3
"""tripletTools per-participant embeddings Condor workflow driver (Python orchestrator).

Fits a SEPARATE embedding for each unique worker_id in a combined triplet
dataset -- one Condor job per participant -- then concatenates every
resulting embedding into a single CSV indexed by worker_id and item name.
Useful when you want per-individual embeddings for many participants:
fitting them one at a time locally (even with multicore parallelization,
e.g. via future/future.apply under run_embeddings_from_list()) can take a
long time, and each participant's fit is completely independent of every
other's, making this an easy case to parallelize across a cluster instead.

This is the large-scale companion to run_embeddings_from_list()'s
"individual" output element -- same underlying fit
(run_group_embedding_from_list() applied to one participant's own
triplets), just parallelized across Condor jobs instead of iterated over
(optionally in parallel via future/future.apply) on a single machine.

Runs, on an HTCondor cluster, in a single Condor stage plus local
aggregation:
  1. Fit: one job per unique worker_id in the input triplet data, each
     fitting that participant's own embedding from their own triplets
     only. All submitted together as a single queue block.
  2. Aggregate (local, not a Condor job): once every fit job has finished,
     concatenate all per-worker embedding CSVs (each already tagged with
     its own worker_id column by condor_individual_fit.R) into one
     embeddings.csv, indexed by worker_id and item.

Every fit job runs condor_individual_fit.R (in this same directory) inside
the tripletTools container image via HTCondor's container universe -- no R
installation is needed on the submit node, only Python and this script.

Usage:
    python3 condor_individual_embeddings_workflow.py <triplet_data.csv> <params.yml>

<triplet_data.csv> must be a combined CSV in the format get.combined()
reads (one row per triplet judgment, with a worker_id column). See
inst/extdata/icon_all_triplets.csv for an example.

<params.yml> follows individual_embeddings_params_template.yml in this same
directory.
"""
import argparse
import csv
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
CONDOR_INDIVIDUAL_FIT_R = SCRIPT_DIR / "condor_individual_fit.R"


# ---------------------------------------------------------------------------
# Config / IO helpers
# ---------------------------------------------------------------------------

def get_config(config, field, default=None):
    value = config.get(field)
    return value if value is not None else default


# Columns run_group_embedding_from_list() (via condor_individual_fit.R)
# actually reads. A real combined triplet export commonly carries several
# more (head, winner, loser, rt, sampleAlg, ...) that are never read
# downstream and would otherwise be rewritten into every one of potentially
# thousands of per-worker output files -- see condor_group_diff_workflow.py's
# identical rationale for HARD_/SOFT_REQUIRED_COLUMNS and the quadratic-scan
# bug that trimming (and grouping rows once, up front) fixed there.
HARD_REQUIRED_COLUMNS = ["Center", "Left", "Right", "Answer"]
SOFT_REQUIRED_COLUMNS = ["sampleSet"]


def read_triplet_rows(path):
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        rows = list(reader)
    if "worker_id" not in (fieldnames or []):
        sys.exit(f"{path} has no 'worker_id' column -- not a valid combined triplet CSV.")

    missing_hard = [c for c in HARD_REQUIRED_COLUMNS if c not in fieldnames]
    if missing_hard:
        sys.exit(f"{path} is missing required column(s): {', '.join(missing_hard)}")

    missing_soft = [c for c in SOFT_REQUIRED_COLUMNS if c not in fieldnames]
    if missing_soft:
        print(f"[condor_individual_embeddings] Note: {path} has no {', '.join(missing_soft)} "
              "column -- run_group_embedding_from_list() will fall back to a "
              "random 70/30 train/test split for every fit.")

    keep_fields = ["worker_id"] + [c for c in HARD_REQUIRED_COLUMNS + SOFT_REQUIRED_COLUMNS
                                    if c in fieldnames]
    trimmed_rows = [{c: row[c] for c in keep_fields} for row in rows]
    return keep_fields, trimmed_rows


def group_rows_by_worker(rows):
    """Group rows once, up front, so writing each worker's own filtered CSV
    only touches that worker's own rows instead of re-scanning the full
    dataset once per worker -- same fix, and same rationale, as
    condor_group_diff_workflow.py's helper of the same name."""
    grouped = {}
    for row in rows:
        grouped.setdefault(row["worker_id"], []).append(row)
    return grouped


def write_filtered_csv(path, fieldnames, rows):
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def aggregate_embeddings(work_dir, stage1_dir, jobs):
    """Concatenate every per-worker embedding CSV (jobs: list of
    (worker_data_name, embedding_name, worker_id, fit_seed) tuples, in the
    order fit jobs were built) into one embeddings.csv, indexed by
    worker_id and item. Each per-worker CSV is already self-describing
    (condor_individual_fit.R writes its own worker_id column), so this is a
    plain read-and-concatenate, not a join."""
    output_rows = []
    dim_cols = None
    for _worker_data_name, embedding_name, worker_id, _fit_seed in jobs:
        path = stage1_dir / embedding_name
        if not path.exists():
            sys.exit(f"Expected fit output missing: {path} (worker_id={worker_id}). "
                      "Check stage1_fit/fit_*.err for that job's failure.")
        with open(path, newline="") as f:
            reader = csv.DictReader(f)
            if dim_cols is None:
                dim_cols = [c for c in reader.fieldnames if c not in ("worker_id", "item")]
            output_rows.extend(list(reader))

    out_path = work_dir / "embeddings.csv"
    fieldnames = ["worker_id", "item"] + (dim_cols or [])
    with open(out_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(output_rows)
    return out_path


# ---------------------------------------------------------------------------
# Submit-file generation and job execution (generic Condor helpers --
# duplicated from the other two orchestrator scripts in this directory by
# design: each Condor workflow here is meant to be self-contained, not to
# share a module between orchestrators)
# ---------------------------------------------------------------------------

def write_submit_file(path, *, container_image, arguments, transfer_input_files,
                       log, output, error, resources, initialdir,
                       queue_statement="queue\n"):
    content = f"""universe        = container
container_image = {container_image}

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
    print(f"[condor_individual_embeddings] Submitting {label} ({submit_path.name})...")
    result = subprocess.run(["condor_submit", str(submit_path)],
                             capture_output=True, text=True)
    print(result.stdout.strip())
    if result.returncode != 0:
        sys.exit(f"condor_submit failed for {label}:\n{result.stderr}")

    print(f"[condor_individual_embeddings] Waiting for {label} to finish "
          f"(condor_wait {log_path})...")
    wait = subprocess.run(["condor_wait", str(log_path)])
    if wait.returncode != 0:
        sys.exit(
            f"condor_wait exited with status {wait.returncode} for {label}. "
            f"Check {log_path} and the corresponding .out/.err files for "
            "held or failed jobs (condor_q -hold, condor_q -better-analyze)."
        )


def queue_from_block(varnames, rows):
    lines = [f"queue {','.join(varnames)} from ("]
    lines += [f"  {','.join(str(v) for v in row)}" for row in rows]
    lines.append(")\n")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Stage
# ---------------------------------------------------------------------------

def run_fit_stage(work_dir, worker_ids, fieldnames, rows_by_worker, config,
                   resources, container_image):
    stage_dir = work_dir / "stage1_fit"
    data_dir = stage_dir / "data"
    data_dir.mkdir(parents=True, exist_ok=True)

    d            = config["d"]
    max_epochs   = get_config(config, "max_epochs", 50000)
    tolerance    = get_config(config, "tolerance", 1e-4)
    tol_window   = get_config(config, "tol_window", 10000)
    device       = get_config(config, "device", "cpu")
    geometry     = get_config(config, "geometry", "euclidean")
    radius       = get_config(config, "radius", 1)
    norm_penalty = get_config(config, "norm_penalty", 0)
    seed         = int(config.get("seed", 1))

    # Jobs are indexed by position (worker0.csv, worker1.csv, ...), not by
    # the raw worker_id string, so an arbitrary worker_id (which could
    # contain characters unsafe in a filename) never has to appear in a
    # path -- it only ever appears inside file *contents* (as a Condor
    # `arguments` value, and as the worker_id column condor_individual_fit.R
    # writes).
    jobs = []  # (worker_data_name, embedding_name, worker_id, fit_seed)
    for i, wid in enumerate(worker_ids):
        worker_data_name = f"worker{i}.csv"
        write_filtered_csv(data_dir / worker_data_name, fieldnames, rows_by_worker[wid])
        embedding_name = f"embedding_worker{i}.csv"
        fit_seed = seed + i
        jobs.append((worker_data_name, embedding_name, wid, fit_seed))

    fixed_args = (
        "condor_individual_fit.R --triplet_data=$(worker_data) --worker_id=$(worker_id) "
        f"--output=$(embedding_out) --d={d} --seed=$(fit_seed) "
        f"--max_epochs={max_epochs} --tolerance={tolerance} --tol_window={tol_window} "
        f"--device={device} --geometry={geometry} --radius={radius} "
        f"--norm_penalty={norm_penalty}"
    )

    submit_path = stage_dir / "fit.sub"
    write_submit_file(
        submit_path,
        container_image=container_image,
        arguments=fixed_args,
        transfer_input_files=f"{CONDOR_INDIVIDUAL_FIT_R}, data/$(worker_data)",
        log=str(stage_dir / "fit.log"),
        output=str(stage_dir / "fit_$(Process).out"),
        error=str(stage_dir / "fit_$(Process).err"),
        resources=resources,
        initialdir=str(stage_dir),
        queue_statement=queue_from_block(
            ["worker_data", "embedding_out", "worker_id", "fit_seed"], jobs
        ),
    )

    submit_and_wait(submit_path, stage_dir / "fit.log", "Stage 1 (per-participant fits)")
    return stage_dir, jobs


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

    for p in (args.triplet_data, args.params):
        if not p.exists():
            sys.exit(f"file not found: {p}")

    with open(args.params) as f:
        config = yaml.safe_load(f) or {}

    if "d" not in config:
        sys.exit("params.yml must set 'd' -- choose it beforehand (e.g. via a local "
                  "estimate_dimensionality() run on the pooled data), so every "
                  "participant's embedding shares the same dimensionality and stays "
                  "directly comparable.")
    config["d"] = int(config["d"])
    if config["d"] < 1:
        sys.exit("params.yml's 'd' must be at least 1.")

    work_dir = Path(config.get("output_dir", "condor_individual_embeddings_output")).resolve()
    work_dir.mkdir(parents=True, exist_ok=True)
    args.triplet_data = args.triplet_data.resolve()

    fieldnames, rows = read_triplet_rows(args.triplet_data)
    rows_by_worker = group_rows_by_worker(rows)

    worker_ids = sorted(rows_by_worker.keys())
    if not worker_ids:
        sys.exit(f"{args.triplet_data} contains no rows.")

    bad_ids = [w for w in worker_ids if "," in w]
    if bad_ids:
        sys.exit(
            "worker_id values must not contain commas (used as the Condor queue "
            f"block's field separator): {bad_ids}"
        )

    condor_cfg = config.get("condor") or {}
    container_image = condor_cfg.get(
        "container_image",
        "docker://ghcr.io/knowledge-and-concepts-lab/triplettools:latest",
    )
    resources = condor_cfg.get("resources") or {}

    print(f"[condor_individual_embeddings] {len(worker_ids)} participants, d={config['d']}")

    stage1_dir, jobs = run_fit_stage(work_dir, worker_ids, fieldnames, rows_by_worker,
                                      config, resources, container_image)

    out_path = aggregate_embeddings(work_dir, stage1_dir, jobs)

    manifest = [
        f"Run finished:    {__import__('datetime').datetime.utcnow().isoformat()}Z",
        f"triplet_data:    {args.triplet_data}",
        f"config:          {args.params.resolve()}",
        f"n_participants:  {len(worker_ids)}",
        f"d:               {config['d']}",
        f"container_image: {container_image}",
        f"output:          {out_path}",
    ]
    (work_dir / "run_manifest.txt").write_text("\n".join(manifest) + "\n")

    print(f"[condor_individual_embeddings] Done. {len(worker_ids)} embeddings written to {out_path}")


if __name__ == "__main__":
    main()
