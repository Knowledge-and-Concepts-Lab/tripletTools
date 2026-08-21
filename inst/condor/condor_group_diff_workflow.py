#!/usr/bin/env python3
"""tripletTools group-difference Condor workflow driver (Python orchestrator).

Tests whether two participant groups' embeddings differ reliably: fits a
separate group embedding for each true group and measures their Procrustes
correlation, then compares that to a null distribution built by repeatedly
re-partitioning the pooled participants at random -- preserving the true
groups' sizes -- and measuring the same correlation between the resulting
pseudo-groups. If the true groups align reliably *worse* than same-sized
random partitions do, that's evidence the groups differ in how they
represent the items, beyond ordinary between-participant variability.

This is the large-scale companion to the local R function
group_difference_test() (same statistical procedure: same size-matched
null partitioning, same one-sided p-value) -- see that function's
documentation for the full rationale. The two are independent
implementations of the same procedure, not guaranteed to reproduce
identical numbers given "the same" seed (participant partitioning uses
Python's random module here, R's sample() there) -- only the same logic.

Runs, on an HTCondor cluster, in two stages:
  1. Fit: one job per (replicate, side) pair -- the true split contributes
     2 jobs (real group 1, real group 2), and each of n_permutations null
     replicates contributes 2 more (pseudo-side A, pseudo-side B). All
     submitted together as a single queue block.
  2. Compare: one job per replicate (1 + n_permutations jobs), each reading
     that replicate's two just-fitted embeddings and computing their
     Procrustes correlation via get.rep.dist(). Only submitted after every
     fit job has completed.

Every job runs condor_group_fit.R / condor_group_compare.R (in this same
directory) inside the tripletTools container image via HTCondor's
container universe -- no R installation is needed on the submit node, only
Python and this script.

Usage:
    python3 condor_group_diff_workflow.py <triplet_data.csv> <group_labels.csv> <params.yml>

<triplet_data.csv> must be a combined CSV in the format get.combined()
reads (one row per triplet judgment, with a worker_id column). See
inst/extdata/icon_all_triplets.csv for an example.

<group_labels.csv> must have columns worker_id, group, covering exactly the
worker IDs present in <triplet_data.csv>, with exactly two distinct group
values.

<params.yml> follows group_diff_params_template.yml in this same directory.
"""
import argparse
import csv
import random
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
CONDOR_GROUP_FIT_R = SCRIPT_DIR / "condor_group_fit.R"
CONDOR_GROUP_COMPARE_R = SCRIPT_DIR / "condor_group_compare.R"


# ---------------------------------------------------------------------------
# Config / IO helpers
# ---------------------------------------------------------------------------

def get_config(config, field, default=None):
    value = config.get(field)
    return value if value is not None else default


def read_triplet_rows(path):
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        rows = list(reader)
    if "worker_id" not in (fieldnames or []):
        sys.exit(f"{path} has no 'worker_id' column -- not a valid combined triplet CSV.")
    return fieldnames, rows


def read_group_labels(path):
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    missing = {"worker_id", "group"} - set(rows[0].keys() if rows else [])
    if missing:
        sys.exit(f"{path} is missing required column(s): {', '.join(sorted(missing))}")
    return {row["worker_id"]: row["group"] for row in rows}


def write_filtered_csv(path, fieldnames, rows, worker_ids):
    keep = set(worker_ids)
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            if row["worker_id"] in keep:
                writer.writerow(row)


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
# Replicate assignment (pure logic, unit-tested)
# ---------------------------------------------------------------------------

def build_replicates(worker_ids, true_groups, n1, n2, n_permutations, seed):
    """Build the list of replicates to fit: replicate 0 is the true split;
    replicates 1..n_permutations are random same-sized (n1, n2) partitions of
    the pooled worker_ids. Returns a list of dicts with keys
    replicate_id, is_true, side_a (list of worker_ids), side_b (list of
    worker_ids).

    Null replicates are drawn at the *same sizes* as the true groups, not a
    blanket 50/50 split -- embedding quality depends on how much data went
    into it, so comparing an unequal true split against evenly-sized random
    halves would confound sample size with genuine group differences.
    """
    group_levels = sorted(set(true_groups.values()))
    replicates = [{
        "replicate_id": 0,
        "is_true": True,
        "side_a": [w for w in worker_ids if true_groups[w] == group_levels[0]],
        "side_b": [w for w in worker_ids if true_groups[w] == group_levels[1]],
    }]

    for i in range(1, n_permutations + 1):
        rng = random.Random(seed + i)
        shuffled = list(worker_ids)
        rng.shuffle(shuffled)
        replicates.append({
            "replicate_id": i,
            "is_true": False,
            "side_a": shuffled[:n1],
            "side_b": shuffled[n1:n1 + n2],
        })

    return replicates


def permutation_p_value(observed, null_values):
    """One-sided permutation p-value: small when `observed` sits in the
    extreme *low* tail of the null distribution -- the direction that
    indicates the true groups align reliably worse than random partitions
    of the same sizes do."""
    n = len(null_values)
    n_as_extreme = sum(1 for x in null_values if x <= observed)
    return (1 + n_as_extreme) / (1 + n)


# ---------------------------------------------------------------------------
# Submit-file generation and job execution (generic Condor helpers --
# duplicated from condor_workflow.py by design: these two orchestrator
# scripts are meant to be self-contained, not to share a library module)
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
    print(f"[condor_group_diff] Submitting {label} ({submit_path.name})...")
    result = subprocess.run(["condor_submit", str(submit_path)],
                             capture_output=True, text=True)
    print(result.stdout.strip())
    if result.returncode != 0:
        sys.exit(f"condor_submit failed for {label}:\n{result.stderr}")

    print(f"[condor_group_diff] Waiting for {label} to finish "
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
# Stages
# ---------------------------------------------------------------------------

def run_fit_stage(work_dir, replicates, fieldnames, rows, config, resources,
                   container_image):
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

    jobs = []  # (side_data_filename, embedding_filename, fit_seed)
    for rep in replicates:
        for side_label, worker_ids in (("A", rep["side_a"]), ("B", rep["side_b"])):
            side_data_name = f"rep{rep['replicate_id']}_side{side_label}.csv"
            write_filtered_csv(data_dir / side_data_name, fieldnames, rows, worker_ids)
            embedding_name = f"embedding_rep{rep['replicate_id']}_side{side_label}.csv"
            # Distinct, deterministic fit seed per (replicate, side); the
            # true split (replicate 0) uses seeds seed*2, seed*2+1 so it
            # never collides with a null replicate's seeds.
            side_index = 0 if side_label == "A" else 1
            fit_seed = seed + rep["replicate_id"] * 2 + side_index
            jobs.append((side_data_name, embedding_name, fit_seed))

    fixed_args = (
        f"condor_group_fit.R --triplet_data=$(side_data) --output=$(embedding_out) "
        f"--d={d} --seed=$(fit_seed) "
        f"--max_epochs={max_epochs} --tolerance={tolerance} --tol_window={tol_window} "
        f"--device={device} --geometry={geometry} --radius={radius} "
        f"--norm_penalty={norm_penalty}"
    )

    submit_path = stage_dir / "fit.sub"
    write_submit_file(
        submit_path,
        container_image=container_image,
        arguments=fixed_args,
        transfer_input_files=f"{CONDOR_GROUP_FIT_R}, data/$(side_data)",
        log=str(stage_dir / "fit.log"),
        output=str(stage_dir / "fit_$(Process).out"),
        error=str(stage_dir / "fit_$(Process).err"),
        resources=resources,
        initialdir=str(stage_dir),
        queue_statement=queue_from_block(
            ["side_data", "embedding_out", "fit_seed"], jobs
        ),
    )

    submit_and_wait(submit_path, stage_dir / "fit.log", "Stage 1 (embedding fits)")
    return stage_dir


def run_compare_stage(work_dir, stage1_dir, replicates, resources, container_image):
    stage_dir = work_dir / "stage2_compare"
    stage_dir.mkdir(parents=True, exist_ok=True)

    # Two variables per embedding: *_src is where write_submit_file finds the
    # file to transfer (relative to this stage's initialdir, i.e. reaching
    # back into stage1_fit/); *_name is the bare filename the file lands
    # under inside the job's sandbox after transfer (HTCondor strips any
    # directory component from transfer_input_files -- confirmed by
    # condor_workflow.py's identical pattern: an absolute data_path is
    # transferred, then referenced in arguments via just data_path.name).
    # Using the *_src value in `arguments` would be wrong -- that path only
    # makes sense on the submit node, not inside the job's sandbox.
    jobs = []
    for rep in replicates:
        emb_a_name = f"embedding_rep{rep['replicate_id']}_sideA.csv"
        emb_b_name = f"embedding_rep{rep['replicate_id']}_sideB.csv"
        output = f"compare_{rep['replicate_id']}.csv"
        jobs.append((
            f"../stage1_fit/{emb_a_name}", f"../stage1_fit/{emb_b_name}",
            emb_a_name, emb_b_name, output,
            rep["replicate_id"], "TRUE" if rep["is_true"] else "FALSE",
        ))

    fixed_args = (
        "condor_group_compare.R --embedding_a=$(embedding_a_name) "
        "--embedding_b=$(embedding_b_name) --output=$(output) "
        "--replicate_id=$(replicate_id) --is_true=$(is_true)"
    )

    submit_path = stage_dir / "compare.sub"
    write_submit_file(
        submit_path,
        container_image=container_image,
        arguments=fixed_args,
        transfer_input_files=f"{CONDOR_GROUP_COMPARE_R}, $(embedding_a_src), $(embedding_b_src)",
        log=str(stage_dir / "compare.log"),
        output=str(stage_dir / "compare_$(Process).out"),
        error=str(stage_dir / "compare_$(Process).err"),
        resources=resources,
        initialdir=str(stage_dir),
        queue_statement=queue_from_block(
            ["embedding_a_src", "embedding_b_src", "embedding_a_name",
             "embedding_b_name", "output", "replicate_id", "is_true"], jobs
        ),
    )

    submit_and_wait(submit_path, stage_dir / "compare.log", "Stage 2 (comparisons)")

    results = []
    for rep in replicates:
        path = stage_dir / f"compare_{rep['replicate_id']}.csv"
        with open(path, newline="") as f:
            row = next(csv.DictReader(f))
        results.append({
            "replicate_id": int(row["replicate_id"]),
            "is_true": row["is_true"] in ("TRUE", "True", "true"),
            "correlation": float(row["correlation"]),
        })
    return results


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                      formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("triplet_data", type=Path,
                         help="Combined CSV in the format get.combined() reads")
    parser.add_argument("group_labels", type=Path,
                         help="CSV with worker_id, group columns for the true split")
    parser.add_argument("params", type=Path, help="YAML config file")
    args = parser.parse_args()

    for p in (args.triplet_data, args.group_labels, args.params):
        if not p.exists():
            sys.exit(f"file not found: {p}")

    with open(args.params) as f:
        config = yaml.safe_load(f) or {}

    if "d" not in config:
        sys.exit("params.yml must set 'd' -- choose it beforehand (e.g. via a local "
                  "estimate_dimensionality() run on the pooled data); it is not "
                  "re-selected per replicate.")
    config["d"] = int(config["d"])
    if config["d"] < 1:
        sys.exit("params.yml's 'd' must be at least 1.")

    work_dir = Path(config.get("output_dir", "condor_group_diff_output")).resolve()
    work_dir.mkdir(parents=True, exist_ok=True)
    args.triplet_data = args.triplet_data.resolve()
    args.group_labels = args.group_labels.resolve()

    fieldnames, rows = read_triplet_rows(args.triplet_data)
    true_groups = read_group_labels(args.group_labels)

    triplet_worker_ids = {row["worker_id"] for row in rows}
    if set(true_groups.keys()) != triplet_worker_ids:
        sys.exit(
            "group_labels and triplet_data must cover exactly the same worker IDs.\n"
            f"In triplet_data but not group_labels: {sorted(triplet_worker_ids - set(true_groups.keys()))}\n"
            f"In group_labels but not triplet_data: {sorted(set(true_groups.keys()) - triplet_worker_ids)}"
        )

    group_levels = sorted(set(true_groups.values()))
    if len(group_levels) != 2:
        sys.exit(f"group_labels must have exactly two distinct group values; found {group_levels}")

    worker_ids = sorted(true_groups.keys())
    n1 = sum(1 for w in worker_ids if true_groups[w] == group_levels[0])
    n2 = len(worker_ids) - n1
    if n1 < 3 or n2 < 3:
        sys.exit(f"Each group must contain at least 3 participants (got {n1}, {n2}).")

    n_permutations = int(config.get("n_permutations", 999))
    seed = int(config.get("seed", 1))

    condor_cfg = config.get("condor") or {}
    container_image = condor_cfg.get(
        "container_image",
        "docker://ghcr.io/knowledge-and-concepts-lab/triplettools:latest",
    )
    resources = condor_cfg.get("resources") or {}

    print(f"[condor_group_diff] {len(worker_ids)} participants: "
          f"{group_levels[0]}={n1}, {group_levels[1]}={n2}; "
          f"n_permutations={n_permutations}, d={config['d']}")

    replicates = build_replicates(worker_ids, true_groups, n1, n2, n_permutations, seed)

    stage1_dir = run_fit_stage(work_dir, replicates, fieldnames, rows,
                               config, resources, container_image)
    results = run_compare_stage(work_dir, stage1_dir, replicates, resources, container_image)

    observed = next(r["correlation"] for r in results if r["is_true"])
    null_values = [r["correlation"] for r in results if not r["is_true"]]
    p_value = permutation_p_value(observed, null_values)

    write_csv(work_dir / "null_distribution.csv", results)

    summary = [{
        "observed_correlation": observed,
        "n_permutations": len(null_values),
        "mean_null_correlation": statistics.fmean(null_values),
        "sd_null_correlation": statistics.stdev(null_values) if len(null_values) > 1 else "",
        "p_value": p_value,
    }]
    write_csv(work_dir / "summary.csv", summary)

    manifest = [
        f"Run finished:         {__import__('datetime').datetime.utcnow().isoformat()}Z",
        f"triplet_data:         {args.triplet_data}",
        f"group_labels:         {args.group_labels}",
        f"config:               {args.params.resolve()}",
        f"group sizes:          {group_levels[0]}={n1}, {group_levels[1]}={n2}",
        f"d:                    {config['d']}",
        f"n_permutations:       {n_permutations}",
        f"observed_correlation: {observed}",
        f"p_value:              {p_value}",
        f"container_image:      {container_image}",
    ]
    (work_dir / "run_manifest.txt").write_text("\n".join(manifest) + "\n")

    print(f"[condor_group_diff] observed_correlation={observed:.4f}  p_value={p_value:.4f}")
    print(f"[condor_group_diff] Done. Outputs written to {work_dir}/")


if __name__ == "__main__":
    main()
