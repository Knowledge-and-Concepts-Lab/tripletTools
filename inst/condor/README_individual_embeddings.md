# Deploying per-participant embeddings on CHTC

This describes how to run `condor_individual_embeddings_workflow.py` — the
Condor-scale companion to `run_embeddings_from_list()`'s per-individual
output — from a CHTC (or other HTCondor) submit node / access point. It
fits a **separate embedding for each unique `worker_id`** in a triplet
dataset and concatenates the results into one CSV, indexed by `worker_id`
and item name.

No R installation is needed on the submit node. Every actual computation
(each participant's embedding fit) runs inside the `tripletTools` container
image on Condor execute nodes; the local aggregation step that concatenates
results at the end is plain Python and runs on the submit node itself.

## Prerequisites (submit node only)

- Python 3
- PyYAML: `pip install --user pyyaml`
- HTCondor client tools (`condor_submit`, `condor_wait`, `condor_q`) —
  already present on any CHTC access point

## Step 1: Get the workflow scripts

```bash
git clone https://github.com/Knowledge-and-Concepts-Lab/tripletTools.git
# or, if you already have a clone: cd tripletTools && git pull
```

Copy these files into your working directory. This workflow needs only
**one** R script (`condor_individual_fit.R`) — don't confuse it with the
other two Condor workflows in this same directory
(`condor_workflow.py`/`condor_fit.R` for dimensionality search + a single
production embedding, and `condor_group_diff_workflow.py`/
`condor_group_fit.R`/`condor_group_compare.R` for the group-difference
permutation test — both different things from per-participant embeddings):

```bash
cp tripletTools/inst/condor/condor_individual_embeddings_workflow.py .
cp tripletTools/inst/condor/condor_individual_fit.R .
cp tripletTools/inst/condor/individual_embeddings_params_template.yml ./my_params.yml
```

**`condor_individual_fit.R` must live in the same directory as
`condor_individual_embeddings_workflow.py`.** The workflow locates it
relative to its own file path, not relative to whatever directory you
happen to run it from — if it's missing, job submission will fail
immediately (the submit file's `transfer_input_files` will reference a
nonexistent path).

You do **not** need to clone/copy the whole `tripletTools` repo into your
working directory — just these two files (plus the CSV from Step 2).

## Step 2: Prepare your input file

Just **one** file is needed — a combined triplet-judgment CSV: one row per
triplet trial, with (at minimum) columns `worker_id`, `Center`, `Left`,
`Right`, `Answer`, `sampleSet` (the format `get.combined()` reads). See
`inst/extdata/icon_all_triplets.csv` in the repo for a real example of this
format. This is your raw data exactly as collected — the same file you'd
hand to `run_embeddings_from_list()`/`get.combined()` locally. Unlike the
group-difference workflow, no separate labels file is needed — every
distinct `worker_id` found in this file gets its own fit.

Upload it into the same working directory as the two scripts from Step 1.

## Step 3: Choose `d` beforehand

Embedding dimensionality (`d`) is fixed across every participant's fit —
it is never re-selected per worker, since every participant's embedding
needs to share the same dimensionality to be directly comparable
afterward (e.g. via Procrustes alignment, `find_discrepant_items()`, or
classifier-based comparisons). Choose it once, beforehand, e.g. by running
`estimate_dimensionality()` locally on the pooled data.

## Step 4: Edit the config

Open `my_params.yml` and set at minimum:

- `d` — **required**; the workflow refuses to run without it (see Step 3)
- `seed` — each participant's fit gets `seed + (their position in the
  sorted worker_id list)`, so this one value determines every fit's own
  training seed
- `condor.container_image` — defaults to `:latest`. If you've just pushed a
  change to the package and want to be certain you're running that exact
  build rather than risk a stale per-execute-node image cache, pin to the
  commit-SHA tag instead (`:sha-<full 40-char commit SHA>`) — both tags are
  published by every build.
- `condor.resources` / the embedding-fit settings (`max_epochs`, `device`,
  etc.) — see the comments in `individual_embeddings_params_template.yml`
  for what each one does and its default. Per-job resource needs here are
  typically much smaller than the group-difference workflow's, since each
  job fits on only one participant's own triplets rather than a pooled
  group.

## Step 5: Deploy

```bash
python3 condor_individual_embeddings_workflow.py triplet_data.csv my_params.yml
```

This submits one Condor job per unique `worker_id` (all of them together,
so HTCondor negotiates however many can run concurrently) and blocks on
`condor_wait` until every one finishes, then concatenates every resulting
embedding locally into `embeddings.csv`. Since it only *orchestrates* — the
actual fitting all happens as Condor jobs, not in this process — it's safe
to run directly on the access point inside a persistent session
(`screen`/`tmux`/`nohup`) rather than as a Condor job itself.

## Outputs

Written to `output_dir` (default `condor_individual_embeddings_output/`,
set in `my_params.yml`):

| File | Contents |
|---|---|
| `stage1_fit/embedding_workerN.csv` | Each participant's own fitted embedding (`worker_id`, `item`, `dim_0`, `dim_1`, …) |
| `embeddings.csv` | Every participant's embedding concatenated, indexed by `worker_id` and `item` |
| `run_manifest.txt` | Participant count, `d`, container image, for provenance |

## Troubleshooting

If `condor_wait` exits with a nonzero status, a job was held or failed.
Check the printed `.log` path, and the corresponding `.out`/`.err` files in
`stage1_fit/`, then:

```bash
condor_q -hold
condor_q -better-analyze <job-id>
```

are the standard first steps for diagnosing why HTCondor won't run/finish a
job (common causes: a typo'd container image tag, or `request_disk` too
small for the pulled image — see `request_disk` in the config).

If the driver itself exits with "Expected fit output missing" during
aggregation, a fit job silently failed to produce its output file — check
that specific job's `stage1_fit/fit_N.err` for the underlying R error
(e.g. too few triplets for that participant to support a train/test split).
