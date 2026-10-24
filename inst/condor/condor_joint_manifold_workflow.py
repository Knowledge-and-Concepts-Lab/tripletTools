#!/usr/bin/env python3
"""tripletTools joint geometry+choice-model manifold Condor workflow driver.

Jointly estimates, for every participant, a position t_i on a shared 1-D
latent manifold that determines BOTH their own representational geometry
X(t_i) (via an actual re-fit embedding, not just a kernel-weighted average
of other participants' existing fits) AND their own choice-model shape
alpha(t_i) = exp(beta0 + beta1*t_i) -- the "fully rigorous" version of the
joint-manifold idea validated locally (see vignette("condor_workflows_vignette")
for the write-up of the decisive LOO test this workflow scales up). This is
the Condor-scale companion to that local, serial validation: the dominant
cost -- one real embedding refit per participant per outer iteration -- is
embarrassingly parallel within an iteration, so it is farmed out to the
cluster; everything else (GPA alignment, the per-person position search,
and the population-curve refit) is cheap and stays local.

Alternating (coordinate-ascent) structure, repeated for `n_outer`
iterations:
  (a) [Condor, parallel]  refit every participant's own embedding under
      their CURRENT alpha(t_i), warm-started from their previous embedding
      (their original CrowdKernel fit on iteration 1).
  (b) [local, cheap]      re-align the newly-refit embeddings (generalized
      Procrustes), refine each participant's own position via a profiled
      choice-model-likelihood search against their own fitting trials, and
      refit the shared population curve (beta0, beta1) given the updated
      positions.

Only `mode: fit` is implemented so far -- one joint estimate across every
participant, with no held-out evaluation. `mode: loo` (the full
leave-one-out validation, one independent fold per held-out participant)
is a planned follow-up, built the same way but wrapping this same
per-iteration logic across many parallel fold states.

Unlike the other three Condor workflows in this directory, step (b) above
runs as a LOCAL Rscript call on the submit node, not inside the container
via Condor: it needs the same R-side generalized_procrustes()/profiled-
likelihood code already validated locally, and it is cheap enough (seconds,
confirmed during that local validation) that the extra Condor round-trip
isn't worth it. This means, unlike the other three workflows, an R
installation WITH the tripletTools package IS required on the submit node
(only for this one step -- condor_joint_manifold_fit.R, the expensive part,
still runs entirely inside the container via Condor, same as everywhere
else in this directory).

Usage:
    python3 condor_joint_manifold_workflow.py <triplet_data.csv> <embeddings.csv> <params.yml>

<triplet_data.csv>: combined CSV in the format get.combined() reads (one
row per triplet judgment, with worker_id, Center/Left/Right/Answer,
sampleAlg, sampleSet columns).

<embeddings.csv>: each participant's EXISTING individual embedding (e.g.
from run_embeddings_from_list()'s per-individual output), in the format
get.combined(..., eflag = TRUE) reads: worker_id, item, dim_0, dim_1, ...
columns. Used as the warm start for the very first outer iteration.

<params.yml> follows joint_manifold_params_template.yml in this same
directory.
"""
import argparse
import csv
import math
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
CONDOR_JOINT_MANIFOLD_FIT_R = SCRIPT_DIR / "condor_joint_manifold_fit.R"
CONDOR_JOINT_MANIFOLD_UPDATE_R = SCRIPT_DIR / "condor_joint_manifold_update.R"


# ---------------------------------------------------------------------------
# Config helper
# ---------------------------------------------------------------------------

def get_config(config, field, default=None):
    value = config.get(field)
    return value if value is not None else default


# ---------------------------------------------------------------------------
# Generic Condor helpers (duplicated from the other workflows in this
# directory by design -- each is meant to be self-contained)
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
    print(f"[condor_joint_manifold] Submitting {label} ({submit_path.name})...")
    result = subprocess.run(["condor_submit", str(submit_path)],
                             capture_output=True, text=True)
    print(result.stdout.strip())
    if result.returncode != 0:
        sys.exit(f"condor_submit failed for {label}:\n{result.stderr}")

    print(f"[condor_joint_manifold] Waiting for {label} to finish "
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


def submit_jobs_with_retry(stage_dir, jobs, output_col, build_and_submit, label,
                            batch_size=None, max_retries=5, extra_outputs=None):
    def output_paths(job):
        paths = [stage_dir / job[output_col]]
        if extra_outputs is not None:
            paths.extend(extra_outputs(job))
        return paths

    def is_bad(path):
        return not path.exists() or path.stat().st_size == 0

    batches = [jobs] if not batch_size else [
        jobs[i:i + batch_size] for i in range(0, len(jobs), batch_size)
    ]

    for batch_num, batch in enumerate(batches, start=1):
        remaining = batch
        for attempt in range(1, max_retries + 2):
            build_and_submit(remaining)
            missing = [j for j in remaining if any(is_bad(p) for p in output_paths(j))]
            if not missing:
                break
            batch_note = f" (batch {batch_num}/{len(batches)})" if batch_size else ""
            print(f"[condor_joint_manifold] {label}{batch_note}: {len(missing)} of "
                  f"{len(remaining)} output(s) missing/empty after attempt "
                  f"{attempt} -- retrying ({[j[output_col] for j in missing]})")
            remaining = missing
        else:
            sys.exit(
                f"{label}: {len(remaining)} output(s) still missing/empty after "
                f"{max_retries} retries: {[j[output_col] for j in remaining]}. "
                f"Check their .err files in {stage_dir}/ for what actually happened."
            )


# ---------------------------------------------------------------------------
# Data prep (pure Python/csv -- no R needed for this part)
# ---------------------------------------------------------------------------

def read_combined_triplets(path):
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    required = ["worker_id", "Center", "Left", "Right", "Answer", "sampleAlg"]
    missing = [c for c in required if c not in (rows[0].keys() if rows else [])]
    if missing:
        sys.exit(f"{path} is missing required column(s): {', '.join(missing)}")
    return rows


def read_combined_embeddings(path):
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    required = ["worker_id", "item"]
    missing = [c for c in required if c not in (rows[0].keys() if rows else [])]
    if missing:
        sys.exit(f"{path} is missing required column(s): {', '.join(missing)}")
    dim_cols = [c for c in rows[0].keys() if c not in ("worker_id", "item")]
    return rows, dim_cols


def build_canonical_items(embedding_rows, worker_ids):
    """Item order from the first worker's own block, validated identical
    (as a set) for every other worker -- every participant's embedding
    must cover the same item set for GPA/cmdscale to make sense."""
    by_worker = {}
    for row in embedding_rows:
        by_worker.setdefault(row["worker_id"], []).append(row["item"])
    first_items = by_worker[worker_ids[0]]
    for w in worker_ids[1:]:
        if set(by_worker[w]) != set(first_items):
            sys.exit(f"worker_id {w}'s embedding covers a different item set than "
                      f"{worker_ids[0]}'s -- every participant must share the same items.")
    return first_items, by_worker


def winner_loser_item(row):
    winner = row["Answer"]
    loser = row["Right"] if row["Left"] == winner else row["Left"]
    return winner, loser


def write_csv(path, fieldnames, rows):
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def prep_person_files(work_dir, worker_ids, item_index, triplet_rows_by_worker,
                       embedding_rows_by_worker, item_order):
    setup_dir = work_dir / "setup"
    orig_dir = setup_dir / "original_embeddings"
    mats_dir = setup_dir / "person_mats"
    trials_dir = setup_dir / "person_trials"
    for d in (orig_dir, mats_dir, trials_dir):
        d.mkdir(parents=True, exist_ok=True)

    dim_cols = [c for c in next(iter(embedding_rows_by_worker.values()))[0].keys()
                if c not in ("worker_id", "item")]

    for i, w in enumerate(worker_ids):
        # Original embedding, reindexed to the canonical item order.
        by_item = {r["item"]: r for r in embedding_rows_by_worker[w]}
        orig_rows = [{"item": it, **{c: by_item[it][c] for c in dim_cols}} for it in item_order]
        write_csv(orig_dir / f"person{i}.csv", ["item"] + dim_cols, orig_rows)

        # Train/test (random-trial) matrices for condor_joint_manifold_fit.R,
        # and the pooled random-trial set for condor_joint_manifold_update.R.
        random_rows = [r for r in triplet_rows_by_worker.get(w, []) if r["sampleAlg"] == "random"]
        train_rows, test_rows, all_rows = [], [], []
        for r in random_rows:
            winner, loser = winner_loser_item(r)
            rec = {"head": item_index[r["Center"]], "winner": item_index[winner],
                   "loser": item_index[loser]}
            all_rows.append(rec)
            sample_set = r.get("sampleSet")
            if sample_set == "test":
                test_rows.append(rec)
            else:
                train_rows.append(rec)
        write_csv(mats_dir / f"person{i}_train.csv", ["head", "winner", "loser"], train_rows)
        write_csv(mats_dir / f"person{i}_test.csv", ["head", "winner", "loser"], test_rows)
        write_csv(trials_dir / f"person{i}.csv", ["head", "winner", "loser"], all_rows)

    return setup_dir, orig_dir, mats_dir, trials_dir


# ---------------------------------------------------------------------------
# One outer iteration
# ---------------------------------------------------------------------------

def run_refit_stage(iter_dir, n_people, warm_start_dir, mats_dir, alphas, config,
                     resources, container_image, batch_size):
    stage_dir = iter_dir / "refit"
    embeddings_out_dir = stage_dir / "embeddings"
    embeddings_out_dir.mkdir(parents=True, exist_ok=True)

    d          = config["d"]
    max_epochs = get_config(config, "max_epochs", 6000)
    tolerance  = get_config(config, "tolerance", 1e-4)
    tol_window = get_config(config, "tol_window", 300)
    device     = get_config(config, "device", "cpu")
    seed       = int(config.get("seed", 1))

    jobs = []  # (person_idx, train_name, test_name, init_name, embedding_out_name, alpha)
    for i in range(n_people):
        jobs.append((i, f"person{i}_train.csv", f"person{i}_test.csv",
                     f"person{i}.csv", f"embedding_person{i}.csv", alphas[i]))

    fixed_args_template = (
        "condor_joint_manifold_fit.R --train_triplets=$(train_file) "
        "--test_triplets=$(test_file) --init_embedding=$(init_file) "
        f"--alpha=$(alpha) --output=$(embedding_out) --d={d} "
        "--seed=$(fit_seed) "
        f"--max_epochs={max_epochs} --tolerance={tolerance} --tol_window={tol_window} "
        f"--device={device}"
    )

    def build_and_submit(jobs_subset):
        rows = [(train_name, test_name, init_name, alpha, f"{seed + i}", embedding_out)
                for (i, train_name, test_name, init_name, embedding_out, alpha) in jobs_subset]
        submit_path = stage_dir / "refit.sub"
        write_submit_file(
            submit_path,
            container_image=container_image,
            arguments=fixed_args_template.replace("$(train_file)", "$(train_name)")
                                          .replace("$(test_file)", "$(test_name)")
                                          .replace("$(init_file)", "$(init_name)"),
            transfer_input_files=(
                f"{CONDOR_JOINT_MANIFOLD_FIT_R}, "
                f"{mats_dir}/$(train_name), {mats_dir}/$(test_name), "
                f"{warm_start_dir}/$(init_name)"
            ),
            log=str(stage_dir / "refit.log"),
            output=str(stage_dir / "refit_$(Process).out"),
            error=str(stage_dir / "refit_$(Process).err"),
            resources=resources,
            initialdir=str(embeddings_out_dir),
            queue_statement=queue_from_block(
                ["train_name", "test_name", "init_name", "alpha", "fit_seed", "embedding_out"], rows
            ),
        )
        submit_and_wait(submit_path, stage_dir / "refit.log", "embedding refits")

    submit_jobs_with_retry(embeddings_out_dir, jobs, output_col=4,
                            build_and_submit=build_and_submit,
                            label="embedding refits", batch_size=batch_size)

    # Each job writes its output under a name distinct from its own
    # --init_embedding input (embedding_person{i}.csv vs person{i}.csv) so
    # the two can never collide inside a single job's transfer sandbox
    # (recall condor_workflow.py's own transfer-vs-argument-name lesson:
    # same concern, different direction). condor_joint_manifold_update.R
    # and the next iteration's warm start both expect plain person{i}.csv,
    # so rename here once, locally, after the batch completes.
    for i in range(n_people):
        (embeddings_out_dir / f"embedding_person{i}.csv").replace(embeddings_out_dir / f"person{i}.csv")
    return embeddings_out_dir


def run_update_step(iter_dir, n_people, embeddings_dir, trials_dir, old_positions_path,
                     old_beta0, old_beta1):
    positions_path = iter_dir / "positions.csv"
    beta_path = iter_dir / "beta.csv"
    aligned_dir = iter_dir / "aligned"
    cmd = [
        "Rscript", str(CONDOR_JOINT_MANIFOLD_UPDATE_R),
        f"--n_pool={n_people}", f"--embeddings_dir={embeddings_dir}",
        f"--trials_dir={trials_dir}",
        f"--old_positions={old_positions_path if old_positions_path else 'NULL'}",
        f"--old_beta0={old_beta0}", f"--old_beta1={old_beta1}",
        f"--output_positions={positions_path}", f"--output_beta={beta_path}",
        f"--output_aligned_dir={aligned_dir}",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    print(result.stdout.strip())
    if result.returncode != 0:
        sys.exit(f"condor_joint_manifold_update.R failed:\n{result.stderr}")

    with open(positions_path, newline="") as f:
        positions = [float(r["position"]) for r in csv.DictReader(f)]
    with open(beta_path, newline="") as f:
        beta_row = next(csv.DictReader(f))
    return positions, float(beta_row["beta0"]), float(beta_row["beta1"]), aligned_dir


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                      formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("triplet_data", type=Path)
    parser.add_argument("embeddings", type=Path)
    parser.add_argument("params", type=Path)
    args = parser.parse_args()

    for p in (args.triplet_data, args.embeddings, args.params):
        if not p.exists():
            sys.exit(f"file not found: {p}")

    with open(args.params) as f:
        config = yaml.safe_load(f) or {}

    if "d" not in config:
        sys.exit("params.yml must set 'd'.")
    config["d"] = int(config["d"])

    mode = get_config(config, "mode", "fit")
    if mode != "fit":
        sys.exit(f"mode='{mode}' is not yet implemented -- only 'fit' is supported so far "
                  "(mode='loo', the full leave-one-out validation, is a planned follow-up).")

    n_outer = int(get_config(config, "n_outer", 6))

    work_dir = Path(config.get("output_dir", "condor_joint_manifold_output")).resolve()
    work_dir.mkdir(parents=True, exist_ok=True)

    condor_cfg = config.get("condor") or {}
    container_image = condor_cfg.get(
        "container_image",
        "docker://ghcr.io/knowledge-and-concepts-lab/triplettools:latest",
    )
    resources = condor_cfg.get("resources") or {}
    batch_size = condor_cfg.get("batch_size")

    triplet_rows = read_combined_triplets(args.triplet_data)
    embedding_rows, _dim_cols = read_combined_embeddings(args.embeddings)

    triplet_workers = sorted({r["worker_id"] for r in triplet_rows})
    embedding_workers = sorted({r["worker_id"] for r in embedding_rows})
    worker_ids = sorted(set(triplet_workers) & set(embedding_workers))
    if len(worker_ids) < len(set(triplet_workers) | set(embedding_workers)):
        print(f"[condor_joint_manifold] Note: using the {len(worker_ids)} worker_id(s) "
              "present in both inputs (some worker_ids were only in one of the two files).")
    if len(worker_ids) < 3:
        sys.exit(f"Only {len(worker_ids)} participant(s) in common -- need at least 3 "
                  "for a manifold position to mean anything.")

    item_order, embedding_rows_by_worker = build_canonical_items(embedding_rows, worker_ids)
    item_index = {it: i for i, it in enumerate(item_order)}

    triplet_rows_by_worker = {}
    for r in triplet_rows:
        triplet_rows_by_worker.setdefault(r["worker_id"], []).append(r)

    n_people = len(worker_ids)
    print(f"[condor_joint_manifold] {n_people} participants, {len(item_order)} items, "
          f"d={config['d']}, n_outer={n_outer}, mode={mode}")

    setup_dir, orig_dir, mats_dir, trials_dir = prep_person_files(
        work_dir, worker_ids, item_index, triplet_rows_by_worker, embedding_rows_by_worker, item_order
    )

    positions = None
    beta0, beta1 = 0.0, 0.0
    warm_start_dir = orig_dir
    old_positions_path = None
    aligned_dir = None

    for t in range(1, n_outer + 1):
        iter_dir = work_dir / f"iter{t}"
        iter_dir.mkdir(parents=True, exist_ok=True)

        if positions is None:
            alphas = [1.0] * n_people
        else:
            alphas = [math.exp(beta0 + beta1 * positions[i]) for i in range(n_people)]

        print(f"[condor_joint_manifold] --- outer iteration {t}/{n_outer} ---")
        embeddings_dir = run_refit_stage(iter_dir, n_people, warm_start_dir, mats_dir, alphas,
                                          config, resources, container_image, batch_size)

        positions, beta0, beta1, aligned_dir = run_update_step(
            iter_dir, n_people, embeddings_dir, trials_dir, old_positions_path, beta0, beta1
        )
        old_positions_path = iter_dir / "positions.csv"
        warm_start_dir = embeddings_dir
        print(f"[condor_joint_manifold] iteration {t} done: beta0={beta0:.4f} beta1={beta1:.4f}")

    # ---- Final production output ----
    final_rows = []
    for i, w in enumerate(worker_ids):
        with open(warm_start_dir / f"person{i}.csv", newline="") as f:
            for row in csv.DictReader(f):
                final_rows.append({"worker_id": w, **row})
    dim_cols_final = [c for c in final_rows[0].keys() if c not in ("worker_id", "item")]
    write_csv(work_dir / "final_embeddings.csv", ["worker_id", "item"] + dim_cols_final, final_rows)

    positions_rows = [{"worker_id": w, "position": positions[i]} for i, w in enumerate(worker_ids)]
    write_csv(work_dir / "final_positions.csv", ["worker_id", "position"], positions_rows)

    manifest = [
        f"Run finished:    {__import__('datetime').datetime.utcnow().isoformat()}Z",
        f"triplet_data:    {args.triplet_data.resolve()}",
        f"embeddings:      {args.embeddings.resolve()}",
        f"config:          {args.params.resolve()}",
        f"n_participants:  {n_people}",
        f"d:               {config['d']}",
        f"n_outer:         {n_outer}",
        f"mode:            {mode}",
        f"final beta0:     {beta0}",
        f"final beta1:     {beta1}",
        f"container_image: {container_image}",
    ]
    (work_dir / "run_manifest.txt").write_text("\n".join(manifest) + "\n")

    print(f"[condor_joint_manifold] Done. Final embeddings: {work_dir / 'final_embeddings.csv'}, "
          f"positions: {work_dir / 'final_positions.csv'}")


if __name__ == "__main__":
    main()
