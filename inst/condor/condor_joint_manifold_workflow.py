#!/usr/bin/env python3
"""tripletTools joint geometry+choice-model manifold Condor workflow driver.

Jointly estimates, for every participant, a position t_i on a shared 1-D
latent geometry manifold (via an actual re-fit embedding at that position,
not just a kernel-weighted average of other participants' existing fits)
AND their own choice-model shape alpha_i -- but unlike an earlier coupled
design, alpha_i is NOT a function of t_i. It is estimated independently:
a per-person profiled MLE, shrunk toward a precision-weighted population
mean via a standard random-effects (DerSimonian-Laird) empirical-Bayes
estimate. The coupled alternative (alpha(t) = exp(beta0 + beta1*t), a
smooth function of the same position driving geometry) was tested directly
against this decoupled design on two real datasets and showed no
detectable predictive advantage on the one dataset where it was shown to
matter at all, while risking real harm on a dataset whose geometry carries
no real individual-differences signal (see the lab's own
`triplet_choice_and_loss.Rmd` for the full comparison that motivated this).
Geometry pooling by position is retained -- real structure was found
there, on the dataset this method was validated on -- only alpha's
estimation is decoupled from it.

This is the Condor-scale companion to that local, serial validation: the
dominant cost -- one real embedding refit per participant per outer
iteration -- is embarrassingly parallel within an iteration, so it is
farmed out to the cluster; everything else (GPA alignment, the per-person
position search, and the per-person alpha re-estimation) is cheap and
stays local (in the sense of not needing a neural-network refit -- see
below for where it actually runs).

Alternating (coordinate-ascent) structure, repeated for `n_outer`
iterations:
  (a) [Condor, parallel]  refit every participant's own embedding under
      their CURRENT alpha_i, warm-started from their previous embedding
      (their original CrowdKernel fit on iteration 1).
  (b) [Condor, single job] re-align the newly-refit embeddings (generalized
      Procrustes), refine each participant's own position via a profiled
      choice-model-likelihood search against their own fitting trials
      (scored at their own current, fixed alpha_i -- not a curve
      evaluated at the candidate position), and re-estimate each
      participant's own alpha via the shrinkage procedure above.

Only `mode: fit` is implemented so far -- one joint estimate across every
participant, with no held-out evaluation. `mode: loo` (the full
leave-one-out validation, one independent fold per held-out participant)
is a deliberately deprioritized follow-up, not a near-term one: it mainly
answers a magnitude question (how much does the actual deployed estimator
help a genuinely new participant) that two much cheaper checks --
`loo_trajectory_accuracy()` and the embedding/alpha decomposition in
`summarize_joint_estimation()` -- already answer convincingly for the
existence question, at a fraction of the cost.

Step (b) above runs as its own single-job Condor batch, inside the same
container image as the embedding-refit jobs, NOT as a local Rscript call
on the submit node -- an earlier version did that, on the reasoning that
another Condor round-trip wasn't worth it for something this cheap, but a
real submit node turned out to have no R installation and no clear way to
add one. This keeps the submit node itself free of any R dependency,
matching the other three Condor workflows in this directory.

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
                       queue_statement="queue\n", transfer_output_files=None):
    # HTCondor's default output transfer ("send back whatever's new in the
    # sandbox") reliably picks up new plain files but does not reliably
    # recurse into a newly-created SUBDIRECTORY unless it's named
    # explicitly here -- confirmed on a real deployment: positions.csv/
    # beta.csv (plain files) came back fine, a new aligned/ directory never
    # did. Callers whose job only ever creates flat files (the embedding
    # refits) can leave this unset.
    transfer_output_line = (
        f"transfer_output_files   = {transfer_output_files}\n" if transfer_output_files else ""
    )
    content = f"""universe        = container
container_image = {container_image}

executable          = /usr/local/bin/Rscript
transfer_executable = False
arguments  = {arguments}

initialdir = {initialdir}

transfer_input_files    = {transfer_input_files}
should_transfer_files   = YES
when_to_transfer_output = ON_EXIT
{transfer_output_line}
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
    must cover the same item set for GPA/cmdscale to make sense. Returns
    the item-name order plus each worker's FULL rows (not just item
    names) -- prep_person_files() needs the dim_* columns too."""
    by_worker = {}
    for row in embedding_rows:
        by_worker.setdefault(row["worker_id"], []).append(row)
    first_items = [r["item"] for r in by_worker[worker_ids[0]]]
    for w in worker_ids[1:]:
        if {r["item"] for r in by_worker[w]} != set(first_items):
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
# Resume support
# ---------------------------------------------------------------------------

def write_id_list(path, ids):
    path.write_text("\n".join(ids) + "\n")


def read_id_list(path):
    return [line for line in path.read_text().splitlines() if line]


def check_or_record_ids(setup_dir, worker_ids, item_order):
    """On a fresh run, records the exact worker_id order and item order this
    run started with. On a resume (these files already exist), verifies the
    CURRENT invocation's inputs produce the identical order -- person{i}.csv
    everywhere in this workflow means "the i-th worker in THIS order," so a
    silent mismatch here (e.g. the input CSVs were edited between runs)
    would misattribute every position/embedding to the wrong participant
    rather than fail loudly."""
    worker_ids_path = setup_dir / "worker_ids.txt"
    item_order_path = setup_dir / "item_order.txt"
    if worker_ids_path.exists():
        prior_workers = read_id_list(worker_ids_path)
        if prior_workers != list(worker_ids):
            sys.exit(f"{worker_ids_path} doesn't match the current worker_id list -- "
                      "the input CSVs appear to have changed since this run started. "
                      "Resuming from this output_dir would misattribute positions/embeddings "
                      "to the wrong participants. Use --fresh, or point output_dir at a new location.")
        prior_items = read_id_list(item_order_path)
        if prior_items != list(item_order):
            sys.exit(f"{item_order_path} doesn't match the current item order -- "
                      "the embeddings input appears to have changed since this run started. "
                      "Use --fresh, or point output_dir at a new location.")
    else:
        write_id_list(worker_ids_path, worker_ids)
        write_id_list(item_order_path, item_order)


def read_alpha_csv(path):
    """Reads an alpha.csv (one row per pool member, in pool order) into a
    plain list of alpha values -- the format condor_joint_manifold_update.R
    writes and condor_joint_manifold_fit.R's --alpha expects."""
    with open(path, newline="") as f:
        return [float(r["alpha"]) for r in csv.DictReader(f)]


def iteration_is_complete(iter_dir, n_people):
    def ok(path):
        return path.exists() and path.stat().st_size > 0
    if not ok(iter_dir / "positions.csv") or not ok(iter_dir / "alpha.csv"):
        return False
    embeddings_dir = iter_dir / "refit" / "embeddings"
    return all(ok(embeddings_dir / f"person{i}.csv") for i in range(n_people))


def find_resume_state(work_dir, n_outer, n_people, orig_dir):
    """Scans iter1, iter2, ... for the longest complete PREFIX (an
    incomplete or missing iteration, even if a LATER one looks complete
    from some earlier abandoned attempt, stops the scan -- resuming must
    continue from the first gap, not skip over it). Returns
    (start_t, positions, alphas, warm_start_dir, old_positions_path,
    old_alpha_path) -- start_t=1 with the fresh-start defaults (alpha=1 for
    everyone) if nothing is resumable."""
    last_complete = 0
    for t in range(1, n_outer + 1):
        if iteration_is_complete(work_dir / f"iter{t}", n_people):
            last_complete = t
        else:
            break

    if last_complete == 0:
        return 1, None, [1.0] * n_people, orig_dir, None, None

    iter_dir = work_dir / f"iter{last_complete}"
    with open(iter_dir / "positions.csv", newline="") as f:
        positions = [float(r["position"]) for r in csv.DictReader(f)]
    alphas = read_alpha_csv(iter_dir / "alpha.csv")
    print(f"[condor_joint_manifold] Resuming after iteration {last_complete}/{n_outer} "
          f"(mean alpha={sum(alphas) / len(alphas):.4f})")
    return (last_complete + 1, positions, alphas,
            iter_dir / "refit" / "embeddings", iter_dir / "positions.csv", iter_dir / "alpha.csv")


# ---------------------------------------------------------------------------
# Smoothed (kernel-weighted pooled) final output -- the artifact actually
# validated against the baseline, distinct from each participant's own
# individually-refit embedding (final_embeddings.csv)
# ---------------------------------------------------------------------------

def r_quantile_type7(sorted_x, p):
    """R's default quantile() algorithm (type 7, linear interpolation)."""
    n = len(sorted_x)
    h = (n - 1) * p
    lo = math.floor(h)
    hi = math.ceil(h)
    return sorted_x[lo] + (h - lo) * (sorted_x[hi] - sorted_x[lo])


def bw_nrd0(x):
    """Exact reimplementation of R's stats::bw.nrd0() (Silverman's
    rule-of-thumb bandwidth, the default smooth_embedding_trajectory()/
    condor_joint_manifold_update.R itself uses) -- verified to match R's
    own output bit-for-bit on a reference vector. Must match exactly: this
    bandwidth has to agree with what the R-side update step used to
    produce the `aligned` embeddings being averaged here, or the smoothed
    output wouldn't correspond to the same kernel the method was actually
    validated with."""
    n = len(x)
    mean = sum(x) / n
    sd = (sum((v - mean) ** 2 for v in x) / (n - 1)) ** 0.5
    s = sorted(x)
    iqr = r_quantile_type7(s, 0.75) - r_quantile_type7(s, 0.25)
    lo = min(sd, iqr / 1.34)
    if lo == 0:
        lo = sd if sd else (abs(x[0]) if x[0] else 1.0)
    return 0.9 * lo * n ** (-0.2)


def read_dim_csv(path):
    """Reads a plain dim_0,dim_1,...-only CSV (no item column) -- the
    format aligned/person{i}.csv is written in -- into a list of rows,
    each a list of floats, in file order (matching the canonical item
    order every file in this workflow shares)."""
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        dim_cols = reader.fieldnames
        return [[float(row[c]) for c in dim_cols] for row in reader]


def smoothed_embedding_at(t, positions, bandwidth, aligned_rows_list):
    """Kernel-weighted average across every pool member's aligned embedding
    at query position t -- the same embed_at() used throughout this
    workflow's own position-search step (R side), reimplemented here in
    plain Python so the orchestrator can produce this output without
    needing R. `aligned_rows_list[k]` is pool member k's aligned embedding
    (list of item rows, each a list of d floats); `positions[k]` is their
    corresponding position."""
    weights = [math.exp(-0.5 * ((p - t) / bandwidth) ** 2) for p in positions]
    total = sum(weights)
    weights = [w / total for w in weights]
    n_items = len(aligned_rows_list[0])
    d = len(aligned_rows_list[0][0])
    result = [[0.0] * d for _ in range(n_items)]
    for person_rows, w in zip(aligned_rows_list, weights):
        if w == 0.0:
            continue
        for i in range(n_items):
            for k in range(d):
                result[i][k] += w * person_rows[i][k]
    return result


def grand_mean_embedding(aligned_rows_list):
    """Plain, position-independent average across every pool member's
    aligned embedding -- the same embedding for everyone, no kernel
    weighting at all. Cheap to compute alongside smoothed_embedding_at()
    since both start from the same aligned_rows_list; added after real
    analysis on two datasets (see triplet_choice_and_loss.Rmd) found that
    for a dataset with no real cross-participant geometric structure, this
    plain average beat the position-weighted smoothed estimate just as
    well (indistinguishably, in fact) -- while for a dataset with real
    structure it did not. Reporting both lets a user see which situation
    they're in without a separate ad hoc analysis each time."""
    n_people = len(aligned_rows_list)
    n_items = len(aligned_rows_list[0])
    d = len(aligned_rows_list[0][0])
    result = [[0.0] * d for _ in range(n_items)]
    for person_rows in aligned_rows_list:
        for i in range(n_items):
            for k in range(d):
                result[i][k] += person_rows[i][k] / n_people
    return result


def write_smoothed_outputs(work_dir, n_outer, worker_ids, item_order, positions):
    """Writes final_smoothed_embeddings.csv (the kernel-smoothed pooled
    geometry estimate at each participant's own position -- the artifact
    actually validated as beating the baseline) and
    final_grand_mean_embedding.csv (the plain, position-independent
    average -- see grand_mean_embedding()). Geometry only -- alpha is
    decoupled from position entirely now, so each participant's final
    alpha is just their own value from the last iteration's alpha.csv,
    written separately in main() with no position-dependent computation
    needed. Requires the final iteration's aligned/ directory (added by
    the transfer_output_files fix); skips with a clear message, rather
    than failing the whole run, if it's missing -- e.g. a run from before
    that fix, or an interrupted iteration."""
    aligned_dir = work_dir / f"iter{n_outer}" / "aligned"
    n_people = len(worker_ids)
    missing = [i for i in range(n_people) if not (aligned_dir / f"person{i}.csv").exists()]
    if missing:
        print(f"[condor_joint_manifold] Note: {aligned_dir} is missing or incomplete "
              f"({len(missing)} of {n_people} participant(s)) -- skipping "
              "final_smoothed_embeddings.csv. This needs the final iteration's aligned/ "
              "output (added after the transfer_output_files fix); an older run won't have it.")
        return

    aligned_rows_list = [read_dim_csv(aligned_dir / f"person{i}.csv") for i in range(n_people)]
    bandwidth = bw_nrd0(positions)

    smoothed_rows = []
    for i, w in enumerate(worker_ids):
        X = smoothed_embedding_at(positions[i], positions, bandwidth, aligned_rows_list)
        for item, row in zip(item_order, X):
            smoothed_rows.append({"worker_id": w, "item": item,
                                   **{f"dim_{k}": v for k, v in enumerate(row)}})

    dim_cols = [f"dim_{k}" for k in range(len(aligned_rows_list[0][0]))]
    write_csv(work_dir / "final_smoothed_embeddings.csv", ["worker_id", "item"] + dim_cols, smoothed_rows)

    gm = grand_mean_embedding(aligned_rows_list)
    gm_rows = [{"item": item, **{f"dim_{k}": v for k, v in enumerate(row)}}
               for item, row in zip(item_order, gm)]
    write_csv(work_dir / "final_grand_mean_embedding.csv", ["item"] + dim_cols, gm_rows)

    print(f"[condor_joint_manifold] Wrote {work_dir / 'final_smoothed_embeddings.csv'} "
          f"(bandwidth={bandwidth:.4f}) and {work_dir / 'final_grand_mean_embedding.csv'}")


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
                     old_alpha_path, resources, container_image):
    """Runs condor_joint_manifold_update.R as a single Condor job, inside the
    same container image as the embedding-refit jobs (which already has R +
    tripletTools installed) -- NOT a local subprocess call. This keeps the
    submit node itself free of any R dependency, matching the other three
    Condor workflows in this directory, at the cost of one extra
    submit/wait round-trip per outer iteration for a job cheap enough that
    it finishes in seconds once it starts running.

    `embeddings_dir` and `trials_dir` are transferred as whole directories
    (HTCondor preserves their basename as the landing directory inside the
    job's sandbox), so this relies on both always being named "embeddings"
    and "person_trials" respectively -- true for every caller in this file.
    """
    positions_path = iter_dir / "positions.csv"
    alpha_path = iter_dir / "alpha.csv"
    aligned_dir = iter_dir / "aligned"

    assert embeddings_dir.name == "embeddings"
    assert trials_dir.name == "person_trials"

    transfer_files = [str(CONDOR_JOINT_MANIFOLD_UPDATE_R), str(embeddings_dir), str(trials_dir)]

    def stage(path, staged_name):
        # Staged under a name distinct from this job's own output of the
        # same kind ("positions.csv" / "alpha.csv") so the two can never
        # collide inside the job's transfer sandbox -- same concern, same
        # fix, as the embedding-refit stage's init/output filename split.
        if path is None:
            return "NULL"
        staged = iter_dir / staged_name
        staged.write_bytes(Path(path).read_bytes())
        transfer_files.append(str(staged))
        return staged_name

    old_positions_arg = stage(old_positions_path, "old_positions_input.csv")
    old_alpha_arg = stage(old_alpha_path, "old_alpha_input.csv")

    arguments = (
        f"condor_joint_manifold_update.R --n_pool={n_people} "
        "--embeddings_dir=embeddings --trials_dir=person_trials "
        f"--old_positions={old_positions_arg} --old_alpha={old_alpha_arg} "
        "--output_positions=positions.csv --output_alpha=alpha.csv "
        "--output_aligned_dir=aligned"
    )

    submit_path = iter_dir / "update.sub"
    write_submit_file(
        submit_path,
        container_image=container_image,
        arguments=arguments,
        transfer_input_files=", ".join(transfer_files),
        log=str(iter_dir / "update.log"),
        output=str(iter_dir / "update.out"),
        error=str(iter_dir / "update.err"),
        resources=resources,
        initialdir=str(iter_dir),
        queue_statement="queue\n",
        transfer_output_files="positions.csv, alpha.csv, aligned",
    )
    submit_and_wait(submit_path, iter_dir / "update.log", "manifold update")

    if not positions_path.exists() or not alpha_path.exists():
        sys.exit(f"condor_joint_manifold_update.R did not produce expected output -- "
                 f"check {iter_dir / 'update.err'}")

    with open(positions_path, newline="") as f:
        positions = [float(r["position"]) for r in csv.DictReader(f)]
    alphas = read_alpha_csv(alpha_path)
    return positions, alphas, aligned_dir


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                      formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("triplet_data", type=Path)
    parser.add_argument("embeddings", type=Path)
    parser.add_argument("params", type=Path)
    parser.add_argument("--fresh", action="store_true",
                         help="Ignore any existing iter*/ state in output_dir and start over "
                              "from iteration 1, instead of auto-resuming after the last "
                              "complete iteration (the default).")
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
    check_or_record_ids(setup_dir, worker_ids, item_order)

    if args.fresh:
        start_t, positions, alphas, warm_start_dir, old_positions_path, old_alpha_path = (
            1, None, [1.0] * n_people, orig_dir, None, None
        )
    else:
        start_t, positions, alphas, warm_start_dir, old_positions_path, old_alpha_path = find_resume_state(
            work_dir, n_outer, n_people, orig_dir
        )
    aligned_dir = None

    if start_t > n_outer:
        print(f"[condor_joint_manifold] Already at iteration {start_t - 1}/{n_outer} -- "
              "nothing left to run (pass a larger n_outer in the config to continue further, "
              "or --fresh to restart).")

    for t in range(start_t, n_outer + 1):
        iter_dir = work_dir / f"iter{t}"
        iter_dir.mkdir(parents=True, exist_ok=True)

        print(f"[condor_joint_manifold] --- outer iteration {t}/{n_outer} ---")
        embeddings_dir = run_refit_stage(iter_dir, n_people, warm_start_dir, mats_dir, alphas,
                                          config, resources, container_image, batch_size)

        positions, alphas, aligned_dir = run_update_step(
            iter_dir, n_people, embeddings_dir, trials_dir, old_positions_path, old_alpha_path,
            resources, container_image
        )
        old_positions_path = iter_dir / "positions.csv"
        old_alpha_path = iter_dir / "alpha.csv"
        warm_start_dir = embeddings_dir
        print(f"[condor_joint_manifold] iteration {t} done: "
              f"mean alpha={sum(alphas) / len(alphas):.4f}")

    # ---- Final production output ----
    # NOTE: final_embeddings.csv (below) is each participant's own
    # INDIVIDUALLY-REFIT embedding -- useful for inspection, but NOT the
    # artifact validated as beating the baseline (own individual embedding,
    # standard shared alpha): that comparison was always against the
    # KERNEL-SMOOTHED pooled estimate (embed_at(), a weighted average across
    # the whole aligned pool at each participant's own position), confirmed
    # directly on a real production run where final_embeddings.csv alone
    # showed progressive, spurious-looking "overfitting" across outer
    # iterations that the smoothed estimate (final_smoothed_embeddings.csv,
    # below) did not. Use the smoothed version for any actual prediction.
    final_rows = []
    for i, w in enumerate(worker_ids):
        with open(warm_start_dir / f"person{i}.csv", newline="") as f:
            for row in csv.DictReader(f):
                final_rows.append({"worker_id": w, **row})
    dim_cols_final = [c for c in final_rows[0].keys() if c not in ("worker_id", "item")]
    write_csv(work_dir / "final_embeddings.csv", ["worker_id", "item"] + dim_cols_final, final_rows)

    positions_rows = [{"worker_id": w, "position": positions[i]} for i, w in enumerate(worker_ids)]
    write_csv(work_dir / "final_positions.csv", ["worker_id", "position"], positions_rows)

    # Each participant's own alpha -- already a direct per-person value
    # (regularized via shrinkage in the update step, not a function of
    # position), so no position-dependent computation is needed here, just
    # a pass-through under the worker_id each file in this workflow uses.
    alpha_rows = [{"worker_id": w, "alpha": alphas[i]} for i, w in enumerate(worker_ids)]
    write_csv(work_dir / "final_alpha.csv", ["worker_id", "alpha"], alpha_rows)

    write_smoothed_outputs(work_dir, n_outer, worker_ids, item_order, positions)

    mean_alpha = sum(alphas) / len(alphas)
    manifest = [
        f"Run finished:    {__import__('datetime').datetime.utcnow().isoformat()}Z",
        f"triplet_data:    {args.triplet_data.resolve()}",
        f"embeddings:      {args.embeddings.resolve()}",
        f"config:          {args.params.resolve()}",
        f"n_participants:  {n_people}",
        f"d:               {config['d']}",
        f"n_outer:         {n_outer}",
        f"mode:            {mode}",
        f"alpha estimation: decoupled (per-person, shrinkage-regularized -- not a function of position)",
        f"final mean alpha: {mean_alpha}",
        f"container_image: {container_image}",
    ]
    (work_dir / "run_manifest.txt").write_text("\n".join(manifest) + "\n")

    print(f"[condor_joint_manifold] Done. Final embeddings: {work_dir / 'final_embeddings.csv'}, "
          f"positions: {work_dir / 'final_positions.csv'}")


if __name__ == "__main__":
    main()
