# Deploying the group-difference test on CHTC

This describes how to run `condor_group_diff_workflow.py` — the Condor-scale
companion to the local R function `group_difference_test()` — from a CHTC
(or other HTCondor) submit node / access point. See
`?group_difference_test` (or its roxygen docs in
`R/group_difference_test.R`) for the full statistical rationale; this file
only covers deployment mechanics.

No R installation is needed on the submit node. Every actual computation
(embedding fits, Procrustes comparisons) runs inside the `tripletTools`
container image on Condor execute nodes.

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

Copy **three** files into your working directory — not just one R script.
This workflow needs two R scripts (`condor_group_fit.R` and
`condor_group_compare.R`), and their names are easy to confuse with the
*other* Condor workflow in this same directory (`condor_workflow.py` /
`condor_fit.R`, for dimensionality search + a single production embedding —
a different thing from the group-difference test):

```bash
cp tripletTools/inst/condor/condor_group_diff_workflow.py .
cp tripletTools/inst/condor/condor_group_fit.R .
cp tripletTools/inst/condor/condor_group_compare.R .
cp tripletTools/inst/condor/group_diff_params_template.yml ./my_params.yml
```

**The two R scripts must live in the same directory as
`condor_group_diff_workflow.py`.** The workflow locates them relative to its
own file path, not relative to whatever directory you happen to run it
from — if they're missing from that directory, job submission will fail
immediately (the submit file's `transfer_input_files` will reference a
nonexistent path).

You do **not** need to clone/copy the whole `tripletTools` repo into your
working directory — just these three files (plus the two CSVs from Step 2).

## Step 2: Prepare your two input files

**This is the part most likely to trip you up: the workflow takes raw
triplet judgment data, not precomputed embeddings.** It fits every
embedding itself, twice per replicate (once per group/pseudo-group side) —
that's the whole point of the permutation test. You provide:

1. **A combined triplet-judgment CSV** — one row per triplet trial, with (at
   minimum) columns `worker_id`, `Center`, `Left`, `Right`, `Answer`,
   `sampleSet` (the format `get.combined()` reads). See
   `inst/extdata/icon_all_triplets.csv` in the repo for a real example of
   this format. This is your raw data exactly as collected — the same file
   you'd hand to `run_embeddings_from_list()`/`get.combined()` locally.

2. **A group-labels CSV** — exactly two columns, `worker_id` and `group`:

   ```csv
   worker_id,group
   p001,patient
   p002,patient
   p003,patient
   ...
   p050,control
   ```

   Must cover *exactly* the same worker IDs as the triplet CSV (the workflow
   checks this and exits with a clear error listing any mismatches), with
   exactly two distinct `group` values, each with at least 3 participants.

Upload both files into the same working directory as the three scripts from
Step 1 (`scp`, or however you already move data onto the access point).

## Step 3: Choose `d` beforehand

Embedding dimensionality (`d`) is fixed across the true split *and every
null permutation* — it is never re-selected per replicate, since doing so
would be prohibitively slow (hundreds of permutations × a full
dimensionality search each) and would entangle dimensionality selection
with the group-difference test itself. Choose it once, beforehand, e.g. by
running `estimate_dimensionality()` locally on the pooled (both-groups)
data, or by reusing `d` from a smaller local `group_difference_test()` pilot
run on a subsample.

## Step 4: Edit the config

Open `my_params.yml` and set at minimum:

- `d` — **required**; the workflow refuses to run without it (see Step 3)
- `n_permutations` — default 999; each one costs 2 embedding fits, so total
  Condor jobs = `3 * (1 + n_permutations)` (2 fit jobs + 1 compare job per
  replicate, including the true split)
- `seed` — controls both the random participant partitions and each
  embedding's own fitting seed
- `condor.container_image` — defaults to `:latest`. If you've just pushed a
  change to the package and want to be certain you're running that exact
  build rather than risk a stale per-execute-node image cache, pin to the
  commit-SHA tag instead (`:sha-<full 40-char commit SHA>`) — both tags are
  published by every build.
- `condor.resources` / the embedding-fit settings (`max_epochs`, `device`,
  etc.) — see the comments in `group_diff_params_template.yml` for what
  each one does and its default.

## Step 5: Deploy

```bash
python3 condor_group_diff_workflow.py triplet_data.csv group_labels.csv my_params.yml
```

This submits Stage 1 (one Condor job per (replicate, side) pair — all of
them together, so HTCondor negotiates however many can run concurrently)
and blocks on `condor_wait` until every one finishes; then submits and waits
on Stage 2 (one comparison job per replicate); then aggregates the results
locally. Since it only *orchestrates* — the actual fitting/comparison work
all happens as Condor jobs, not in this process — it's safe to run directly
on the access point inside a persistent session (`screen`/`tmux`/`nohup`)
rather than as a Condor job itself.

## Outputs

Written to `output_dir` (default `condor_group_diff_output/`, set in
`my_params.yml`):

| File | Contents |
|---|---|
| `stage1_fit/embedding_repN_side{A,B}.csv` | Every fitted embedding (true split = replicate 0) |
| `stage2_compare/compare_N.csv` | Each replicate's Procrustes correlation |
| `null_distribution.csv` | All `1 + n_permutations` correlations, with an `is_true` flag |
| `summary.csv` | `observed_correlation`, `p_value`, and null-distribution mean/SD |
| `run_manifest.txt` | Group sizes, `d`, `n_permutations`, the final result, container image, for provenance |

## Troubleshooting

If `condor_wait` exits with a nonzero status, a job in that stage was held
or failed. Check the printed `.log` path, and the corresponding
`.out`/`.err` files in the stage directory, then:

```bash
condor_q -hold
condor_q -better-analyze <job-id>
```

are the standard first steps for diagnosing why HTCondor won't run/finish a
job (common causes: a typo'd container image tag, or `request_disk` too
small for the pulled image — see `request_disk` in the config).
