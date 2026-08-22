# Deploying tripletTools on HTCondor

## Overview

`tripletTools` ships three independent HTCondor workflows for offloading
expensive, embarrassingly-parallel computations — grid searches,
permutation tests, per-participant fits — to a cluster
(e.g. UW–Madison’s CHTC) instead of running them serially (or even
multicore) on your own machine.

All three share the same design: a small, dependency-light **Python**
script (the *orchestrator*) runs on the submit node and does the actual
`condor_submit`/`condor_wait` work — **no R installation is needed on
the submit node**, only Python 3 and PyYAML. Every real computation
(each embedding fit, each comparison) instead runs *inside the
`tripletTools` container image* via HTCondor’s `container` universe,
dispatched as a per-job R script. This split matters because CHTC’s
execute nodes are heterogeneous and ephemeral — you cannot assume any of
them has R, `tripletTools`, or the `triplet-embeddings` conda
environment pre-installed, so every job carries its own environment with
it via the container instead.

| Workflow | What it does | Local R equivalent | Files (all in `inst/condor/`) |
|----|----|----|----|
| Dimensionality search → learning curve → final fit | Picks an embedding dimension, sanity-checks it against a learning curve, and produces a production embedding | [`estimate_dimensionality()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md) / [`estimate_learning_curve()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_learning_curve.md) | `condor_workflow.py`, `condor_fit.R`, `params_template.yml` |
| Group-difference permutation test | Tests whether two participant groups’ embeddings differ reliably, via a size-matched permutation null | [`group_difference_test()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/group_difference_test.md) | `condor_group_diff_workflow.py`, `condor_group_fit.R`, `condor_group_compare.R`, `group_diff_params_template.yml` |
| Per-participant individual embeddings | Fits a separate embedding for every participant, concatenated into one CSV | [`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md) (its “individual” output) | `condor_individual_embeddings_workflow.py`, `condor_individual_fit.R`, `individual_embeddings_params_template.yml` |

Each workflow also has its own quick-reference `README_*.md` alongside
its scripts in `inst/condor/` — this vignette covers the same ground in
more depth and in one place, but the READMEs are there for exactly the
moment you’ve sparse-cloned just `inst/condor/` (see below) and want the
deployment steps without leaving that directory.

------------------------------------------------------------------------

## Prerequisites (submit node only)

- Python 3
- PyYAML: `pip install --user pyyaml`
- HTCondor client tools (`condor_submit`, `condor_wait`, `condor_q`,
  `condor_ssh_to_job`) — already present on any CHTC access point

None of the three workflows need R, conda, or `tripletTools` itself
installed on the submit node. Those are only ever needed inside the
container image that each job runs in.

------------------------------------------------------------------------

## Getting the workflow files: a sparse clone per analysis

The only part of the repository these workflows need is `inst/condor/` —
everything else (the vendored Python embedding backend, R source,
vignettes, bundled example datasets) is irrelevant on the submit node.
At the same time, it’s worth getting a fresh copy **per analysis**
rather than repeatedly reusing one long-lived shared clone: some of
these workflows span hours to days (e.g. a fit stage followed hours
later by a compare stage), and a `git pull` to the shared clone in
between could silently change the code partway through a single run. A
bare copied file, on its own, also carries no record of which commit
produced it.

Combining both concerns — avoid pulling the whole repo, but still get a
verifiable, frozen snapshot — git’s `--filter=blob:none` partial clone
plus `sparse-checkout` does exactly this:

``` bash
git clone --filter=blob:none --no-checkout --depth 1 \
  https://github.com/Knowledge-and-Concepts-Lab/tripletTools.git my_analysis
cd my_analysis
git sparse-checkout init --cone
git sparse-checkout set inst/condor
git checkout main
cd inst/condor
```

`--filter=blob:none` means the server only sends file *contents* for
what you actually check out, not the whole repository’s history of
blobs; `sparse-checkout` then limits the working tree to just
`inst/condor/`. The result is a directory containing only the condor
workflow files — nothing unrelated in sight — while still being a real
git repository, so `git log -1` inside `my_analysis` gives you a
genuine, verifiable record of exactly which commit produced the scripts
you ran.

Two things worth knowing:

- `inst/condor/` is still one directory level below the clone root
  (`my_analysis/inst/condor/`, not `my_analysis/`) — a fixed consequence
  of these files living inside an R package’s `inst/` directory in the
  source repo. In practice you just `cd` into it once and treat it as
  your working directory from then on (uploading data there, editing
  configs there, running the orchestrator there).
- Cone-mode sparse-checkout needs git ≥ 2.25. If that’s ever
  unavailable, fall back to a plain shallow clone
  (`git clone --depth 1 ... my_analysis`) and
  `cd my_analysis/inst/condor` — more bytes on disk, but identical
  otherwise, including the commit-hash provenance.

------------------------------------------------------------------------

## General deployment procedure

Every workflow follows the same shape, once you’re sitting in your
cloned `inst/condor/`:

1.  **Prepare your input data file(s).** At minimum, a combined
    triplet-judgment CSV — one row per triplet trial, with a `worker_id`
    column and the format
    [`get.combined()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md)
    reads (see `inst/extdata/icon_all_triplets.csv` for an example).
    This is your raw data exactly as collected; nothing needs to be
    precomputed. The group-difference workflow additionally needs a
    group-labels CSV (see its section below). Upload data files into the
    same directory as the scripts (`scp`, or however you already move
    data onto the access point).

2.  **Copy the relevant `*_params_template.yml` and edit it.** Every
    field is documented with inline comments in the template itself; at
    minimum you’ll set `output_dir` and (for the two embedding-fitting
    workflows) `d`, chosen beforehand via a local
    [`estimate_dimensionality()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)
    run — never re-selected mid-workflow, since doing so per
    replicate/participant would be prohibitively slow and would entangle
    dimensionality selection with whatever the workflow is actually
    testing.

    ``` bash
    cp params_template.yml my_params.yml   # or group_diff_params_template.yml / individual_embeddings_params_template.yml
    ```

3.  **Run the driver script.** Since it only *orchestrates* — every
    actual embedding fit or comparison runs as its own Condor job, not
    in this process — it’s safe to run directly on the access point
    inside a persistent session (`screen`/`tmux`/`nohup`) rather than as
    a Condor job itself:

    ``` bash
    python3 condor_workflow.py triplet_data.csv my_params.yml
    ```

4.  **Collect outputs from `output_dir`** (set in your edited config)
    once the driver prints its final summary and exits. Each workflow’s
    section below details exactly what lands there.

------------------------------------------------------------------------

## The container image

Every job — regardless of which workflow submitted it — runs inside the
same `tripletTools` container image via `universe = container`, built
from:

    Dockerfile                                # builds the runtime image
    .github/workflows/docker-publish.yml      # builds + publishes it to ghcr.io on push

The image layers a base R install, Miniconda, the `triplet-embeddings`
conda environment (built via this package’s own
[`setup_python_env()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/setup_python_env.md),
so it’s created exactly the way a local install would be), and
`tripletTools` itself. GitHub Actions rebuilds and pushes it to
`ghcr.io/<org>/<repo>` automatically whenever `Dockerfile`, `R/`,
`inst/python/`, `inst/requirements.txt`, `DESCRIPTION`, or the workflow
file itself change on `main` — pure documentation or `inst/condor/`-only
changes do **not** trigger a rebuild. Every build publishes two tags: a
floating `:latest` and an immutable
`:sha-<full 40-character commit SHA>`.

**Pin to a specific SHA tag if you need certainty about which code
ran.** `:latest` moves with every rebuild; a job submitted mid-run under
`:latest` and a job submitted an hour later after someone else pushed a
change could silently run different code. The immutable `:sha-...` tag
never changes once published, so pinning to it in your config gives the
same kind of provenance guarantee as the sparse-clone commit hash above:

``` yaml
condor:
  container_image: docker://ghcr.io/knowledge-and-concepts-lab/triplettools:sha-<full-commit-sha>
```

**Apptainer/HTCondor caches the pulled image per execute node**, which
is fine at the job counts these workflows generate (dozens to a few
thousand per run). If you’re deploying often enough that repeated
`docker://` pulls become a bottleneck, build the image into a `.sif`
once and stage it instead of pulling from the registry every time —
point `condor.container_image` in your config at CHTC’s OSDF/Pelican
staging path convention instead of the `docker://` reference:

``` yaml
condor:
  container_image: osdf:///chtc$ENV(STAGING)/containers/tripletTools_v1.sif
```

(this also needs `requirements = (Target.HasCHTCStaging == true)` added
to the relevant submit file in whichever workflow’s `.py` you’re
running, if you go this route). Give the `.sif` a version suffix and
update the config’s path when you rebuild it, rather than overwriting
the old filename — OSDF/Pelican caches by path, so reusing a filename
can serve stale content.

**Disk requests are sized for the container.** Pulling and unpacking it
(R + conda + PyTorch) adds several GB on top of whatever a job itself
transfers, so every shipped `*_params_template.yml` defaults
`condor.resources.request_disk` to `8GB`. Override it in your copy of
the config if you need more.

**CHTC staging paths**, if your triplet dataset itself is large enough
to need `/staging` rather than ordinary `transfer_input_files` (CHTC’s
general guidance: under 1GB per file stays in `/home`; 1–30GB goes to
personal staging): personal staging areas are at
`/staging/<first letter of your netid>/<netid>`, exposed as `$STAGING`
on access points and `$ENV(STAGING)` in submit files. A job that reads
staging directly needs `requirements = (Target.HasCHTCStaging == true)`.

------------------------------------------------------------------------

## Troubleshooting a job that seems stuck

All three workflows submit jobs the same way, so the same diagnostic
steps apply regardless of which one you’re running.

**Check its status first.**

``` bash
condor_q <cluster>.<proc>
```

`JobStatus = 2` means genuinely running; `5` means held (check
`condor_q -better-analyze <jobid>` for why); a job can also be
legitimately **suspended** (not killed, not held) on a
shared/opportunistic execute slot under CPU contention — check for this
with:

``` bash
condor_q -long <jobid> | grep -E "JobStatus|TotalSuspensions|LastSuspensionTime"
```

A suspended job’s CPU time genuinely stops accruing while paused, then
resumes on its own — nothing is wrong, it’s just waiting its turn.

**A polling-lag caveat before you conclude anything from
`RemoteUserCpu`.** `condor_q`’s numbers come from periodic updates the
execute node pushes back to the schedd (commonly every several minutes),
not a live feed. If you check `RemoteUserCpu` twice only a minute or two
apart and see no change, that may just mean it hasn’t refreshed yet —
not that the job is stalled. Re-check with a longer gap before drawing
conclusions.

**You cannot tail a running job’s `.out`/`.err` for live progress.**
Every submit file here uses `when_to_transfer_output = ON_EXIT`, so
those files only transfer back to the submit node once the job actually
finishes. A quiet local `.out` file means you can’t see it yet, not that
the job is quiet.

**The definitive check, if your pool has it enabled:**

``` bash
condor_ssh_to_job <jobid>
```

This drops you directly into the job’s own running sandbox on the
execute node (ignore any `groups: cannot find name for group ID ...`
warnings on login — harmless noise from resolving container UID/GID
mappings). From there:

``` bash
ps aux              # find the R process; check %CPU and STAT
cat /proc/<pid>/status | grep State
free -h             # memory/swap pressure
df -h .             # disk full in the sandbox?
```

`STAT` of `R`/`S` with nonzero, climbing `%CPU` means it’s genuinely
computing — a job can legitimately take much longer than its siblings
(e.g. `max_epochs`/`tol_window` haven’t triggered early stopping yet, or
it landed on the larger side of an unequal group split) without anything
being wrong. `D` (uninterruptible sleep, usually I/O-blocked) or a
missing/zombied process is a real problem. Exiting this session (`exit`
or Ctrl+D) only closes the debug shell — it does not touch the job’s own
process tree.

**If it really is stuck:** `condor_vacate_job <jobid>` is the right
first move — it evicts the job and lets HTCondor re-match and restart it
fresh, keeping the *same* job ID, so the orchestrator’s `condor_wait`
(which is watching for that specific ID) needs no changes and keeps
working correctly. Only fall back to `condor_rm` + manually resubmitting
that one job (capturing its `Arguments`/`TransferInput` from
`condor_q -long` first, since you’ll need them to rebuild a one-off
submit file) if the same job stalls again after vacating — that points
to something specific to its data or arguments rather than an unlucky
execute node, and a full remove is a more invasive fix worth reserving
for that case.

------------------------------------------------------------------------

## Workflow 1: Dimensionality search, learning curve, and final embedding fit

For the common case of “pick a dimension, check it against a learning
curve, and fit the best embedding,” `condor_workflow.py` runs all three
stages back to back, dispatching every individual fit to HTCondor as its
own job.

``` bash
python3 condor_workflow.py triplet_data.csv my_params.yml
```

This produces, in `output_dir`:

| File | Contents |
|----|----|
| `dimensionality_results.csv` / `dimensionality_summary.csv` | [`estimate_dimensionality()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)’s `results`/`summary`, one Condor job per (dimension, restart) |
| `learning_curve_results.csv` / `learning_curve_summary.csv` | [`estimate_learning_curve()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_learning_curve.md)’s `results`/`summary`, at the `best_d` selected above, one Condor job per (fraction, restart) |
| `best_embedding.csv` | The final embedding, fit at `best_d` on the *full* dataset (item names in the `item` column) |
| `best_embedding_history.csv` | That final fit’s per-epoch training history (loss, accuracy, `norm_ratio`, …) |
| `run_manifest.txt` | Package version, input paths, `best_d`, and final loss, for provenance |

`seed`, `geometry`, `radius`, and `norm_penalty` apply to all three
stages, so they describe one coherent embedding space throughout;
`max_epochs`/`tolerance`/`tol_window`/`device`/`internal_test_frac`/Condor
`resources` can be overridden per stage — see the comments in
`params_template.yml`. See
[`vignette("embedding_vignette")`](https://knowledge-and-concepts-lab.github.io/tripletTools/articles/embedding_vignette.md)
for the full statistical rationale behind `internal_test_frac` and why
the final embedding is a dedicated fit rather than a reused
learning-curve restart.

------------------------------------------------------------------------

## Workflow 2: Group-difference permutation test

`condor_group_diff_workflow.py` tests whether two participant groups’
embeddings differ reliably: it fits a separate embedding for each true
group, measures their Procrustes correlation, and compares that to a
null distribution built from many random re-partitions of the pooled
participants — **matched to the true groups’ sizes**, not a blanket
50/50 split, since embedding quality depends on how much data went into
a fit. See
[`?group_difference_test`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/group_difference_test.md)
for the full statistical rationale (this workflow is its large-scale
Condor companion, same logic, independent implementation).

**This workflow needs two R scripts** (`condor_group_fit.R` and
`condor_group_compare.R`), not one — easy to under-count by analogy to
Workflow 1’s single `condor_fit.R`. Both must be present alongside
`condor_group_diff_workflow.py`, which is already guaranteed if you
sparse-cloned `inst/condor/` as a whole.

**Inputs:** raw triplet-judgment data, not precomputed embeddings —
fitting every embedding is the whole point of the permutation test.

1.  A combined triplet-judgment CSV (see the general procedure above).

2.  A group-labels CSV, exactly two columns:

    ``` csv
    worker_id,group
    p001,patient
    p002,patient
    ...
    p050,control
    ```

    Must cover *exactly* the same worker IDs as the triplet CSV
    (checked, with a clear error listing any mismatches), with exactly
    two distinct `group` values, each with at least 3 participants.

**Choose `d` beforehand** — fixed across the true split and every null
permutation, never re-selected per replicate, since that would be both
prohibitively slow (hundreds of permutations × a full dimensionality
search each) and would entangle dimensionality selection with the
group-difference test itself.

``` bash
python3 condor_group_diff_workflow.py triplet_data.csv group_labels.csv my_params.yml
```

This runs in two Condor stages — Stage 1 fits one embedding per
(replicate, side) pair (the true split contributes 2, each of
`n_permutations` null replicates contributes 2 more), waits for all of
them, then Stage 2 computes one Procrustes comparison per replicate —
followed by local aggregation. Outputs in `output_dir`:

| File | Contents |
|----|----|
| `stage1_fit/embedding_repN_side{A,B}.csv` | Every fitted embedding (true split = replicate 0) |
| `stage2_compare/compare_N.csv` | Each replicate’s Procrustes correlation |
| `null_distribution.csv` | All `1 + n_permutations` correlations, with an `is_true` flag |
| `summary.csv` | `observed_correlation`, `p_value`, and null-distribution mean/SD |
| `run_manifest.txt` | Group sizes, `d`, `n_permutations`, the final result, container image, for provenance |

------------------------------------------------------------------------

## Workflow 3: Per-participant individual embeddings

`condor_individual_embeddings_workflow.py` fits a **separate** embedding
for each unique `worker_id` in a triplet dataset — one Condor job per
participant — then concatenates every result into a single CSV indexed
by `worker_id` and `item`. This is the large-scale companion to
[`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md)’s
per-individual output, for when fitting every participant locally (even
multicore, via `future`/`future.apply`) would take too long.

**Only one input file is needed** — a combined triplet-judgment CSV (see
the general procedure above); every distinct `worker_id` found in it
gets its own fit. Unlike Workflow 2, no separate labels file is
required.

``` bash
python3 condor_individual_embeddings_workflow.py triplet_data.csv my_params.yml
```

This is a single Condor stage (one job per participant) plus a local,
non-Condor concatenation step — there’s no comparison stage, unlike
Workflow 2, since there’s nothing to compare across participants here.
Outputs in `output_dir`:

| File | Contents |
|----|----|
| `stage1_fit/embedding_workerN.csv` | Each participant’s own fitted embedding (`worker_id`, `item`, `dim_0`, `dim_1`, …) |
| `embeddings.csv` | Every participant’s embedding concatenated, indexed by `worker_id` and `item` |
| `run_manifest.txt` | Participant count, `d`, container image, for provenance |

**Choose `d` generously, not exactly.** Unlike the other two workflows,
`d` here does not need to be each participant’s own “correct”
dimensionality — different participants may genuinely have different
latent dimensionality, and re-running a full per-participant
dimensionality search on Condor would be expensive to repeat hundreds of
times. Instead, fit everyone at one shared, generously high `d` (with
headroom above what you’d expect any single participant to need), then
reduce each participant’s own embedding back down locally after pulling
`embeddings.csv` down from the cluster:

``` r

library(tripletTools)

individual <- get.combined("embeddings.csv", eflag = TRUE)   # split back out per worker_id
triplets   <- get.combined("triplet_data.csv")               # same, for the original judgments

result <- reduce_embedding_dimension(
  embedding    = individual[["p001"]],
  triplet_data = triplets[["p001"]],
  variance_threshold = 0.95
)

result$k                # this participant's reduced dimensionality
result$accuracy_full    # accuracy at the original, generous d
result$accuracy         # accuracy at the reduced k -- should be close to accuracy_full
```

[`reduce_embedding_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/reduce_embedding_dimension.md)
reduces via PCA on each participant’s own fitted coordinates (not
classical MDS — the two give identical results when you already have
exact Euclidean coordinates in hand, so MDS would just be a more
expensive detour to the same answer) and reports triplet-prediction
accuracy under the reduced embedding evaluated against *every* triplet
that participant judged, not a held-out subset — deliberately, so the
chosen dimensionality isn’t sensitive to which triplets happened to land
in that participant’s own random train/test split. See
[`?reduce_embedding_dimension`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/reduce_embedding_dimension.md)
for the full rationale and its `diagnostics` output for inspecting the
whole variance/accuracy curve rather than trusting a single threshold
blindly.
