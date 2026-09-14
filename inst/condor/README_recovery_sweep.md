# Deploying the choice-model recovery sweep on CHTC

This describes how to run `condor_recovery_sweep_workflow.py` from a CHTC
(or other HTCondor) submit node / access point. It answers a specific
question: when the choice model used to **fit** an embedding differs from
the choice model that actually **generated** the triplet judgments, how
much does recovery error suffer -- how does that cost scale with how far
apart the two models are, and does that pattern hold up across repeated
random draws, or is it just noise from a single simulation?

Unlike the other three Condor workflows in this directory, this one needs
**no input data file at all** -- it generates its own synthetic ground
truth and simulated triplets, once per replicate, then fits and scores
every (replicate, generating alpha, fitting alpha) combination.

No R installation is needed on the submit node. Ground-truth/triplet
simulation and result aggregation are plain Python (stdlib only, no
numpy) and run on the submit node itself; every embedding fit runs inside
the `tripletTools` container image on Condor execute nodes.

## Prerequisites (submit node only)

- Python 3 (stdlib only for the simulate/aggregate steps -- no numpy
  needed)
- PyYAML: `pip install --user pyyaml`
- HTCondor client tools (`condor_submit`, `condor_wait`, `condor_q`) --
  already present on any CHTC access point

## Step 1: Get the workflow scripts

```bash
git clone https://github.com/Knowledge-and-Concepts-Lab/tripletTools.git
# or, if you already have a clone: cd tripletTools && git pull
```

Copy these files into your working directory. This workflow needs only
**one** R script (`condor_recovery_fit.R`) — don't confuse it with the
other three Condor workflows in this same directory (dimensionality
search + final fit, group-difference permutation test, per-participant
embeddings — all different things from this recovery sweep, and none of
them share code with this one by design):

```bash
cp tripletTools/inst/condor/condor_recovery_sweep_workflow.py .
cp tripletTools/inst/condor/condor_recovery_fit.R .
cp tripletTools/inst/condor/recovery_sweep_params_template.yml ./my_params.yml
```

**`condor_recovery_fit.R` must live in the same directory as
`condor_recovery_sweep_workflow.py`.** The workflow locates it relative to
its own file path, not relative to whatever directory you happen to run
it from — if it's missing, job submission will fail immediately (the
submit file's `transfer_input_files` will reference a nonexistent path).

You do **not** need to clone/copy the whole `tripletTools` repo, and you
do **not** need any input data file — this workflow generates its own.

## Step 2: Edit the config

Open `my_params.yml` and set at minimum:

- `alphas` — the continuum of choice-model shape parameters to cross with
  itself (both as the generating and the fitting model). Use YAML's `.inf`
  literal for the exact Gaussian limit.
- `n_replicates` — number of independent replicate simulations (own ground
  truth, own triplets) to run the whole `alphas` x `alphas` grid on. Total
  fits = `n_replicates * len(alphas)^2` — with the shipped defaults (20
  replicates, 8 alphas) that's 1280 fits, calibrated locally at ~46
  minutes per fit (CPU), i.e. ~980 hours of total fitting work. This is
  exactly why the workflow exists: with the CHTC pool running many fits
  concurrently, wall-clock time is roughly however long the slowest single
  fit takes, not the sum of all 1280. Lower `n_replicates` (e.g. back to 1)
  for a quick single-draw look, or raise it further if you want tighter
  error bars than 20 replicates give.
- `d` — embedding dimensionality, for both the synthetic ground truth
  itself and every recovery fit (Procrustes scoring requires the two to
  match, so this one setting controls both).
- `condor.container_image` — defaults to `:latest`. If you've just pushed
  a change to the package and want to be certain you're running that
  exact build rather than risk a stale per-execute-node image cache, pin
  to the commit-SHA tag instead (`:sha-<full 40-char commit SHA>`) — both
  tags are published by every build.
- `condor.resources` / the embedding-fit settings (`max_epochs`,
  `tol_window`, `device`, etc.) — see the comments in
  `recovery_sweep_params_template.yml` for what each one does and its
  default, and consider running one calibration fit yourself (e.g. by
  running `condor_recovery_fit.R` once by hand, or timing one job) if the
  execute nodes' hardware differs meaningfully from what the shipped
  defaults were calibrated on.

## Step 3: Deploy

```bash
python3 condor_recovery_sweep_workflow.py my_params.yml
```

This first generates every replicate's ground-truth embedding and every
generating alpha's triplet set locally (fast — plain Python, no Condor
job), then submits one Condor job per (replicate, generating alpha,
fitting alpha) combination (all of them together, so HTCondor negotiates
however many can run concurrently) and blocks on `condor_wait` until
every one finishes, then aggregates every result locally. Since it only
*orchestrates* the fit stage — all the actual fitting happens as Condor
jobs, not in this process — it's safe to run directly on the access point
inside a persistent session (`screen`/`tmux`/`nohup`) rather than as a
Condor job itself. With 1280 jobs queued at once, expect it to take a
little longer than the other workflows here for HTCondor to fully
negotiate and place everything, even before any fit itself finishes.

## Outputs

Written to `output_dir` (default `condor_recovery_sweep_output/`, set in
`my_params.yml`):

| File | Contents |
|---|---|
| `stage0_simulate/ground_truth_rep<r>.csv` | Replicate `r`'s synthetic ground-truth embedding (`item`, `dim_0`, `dim_1`, `dim_2`) |
| `stage0_simulate/triplets_rep<r>_gen<alpha>.csv` | Replicate `r`'s simulated triplets (`head`, `winner`, `loser`, 0-based) for each generating alpha |
| `stage1_fit/result_rep<r>_genNfitM.csv` | One (replicate, generating, fitting) combination's recovery error, loss, and stopping epoch |
| `results_long.csv` | Every fit's result, one row each (`replicate`, `gen_alpha`, `fit_alpha`, `recovery_error`, `loss`, `epoch`) — the right input for any real statistical comparison (e.g. a paired test between two fitting alphas for the same generating alpha, across replicates) |
| `error_matrix_mean.csv` / `error_matrix_sd.csv` | `results_long.csv` pivoted into a generating-alpha x fitting-alpha grid of the mean/SD recovery error across replicates — a quick first look, not a substitute for looking at `results_long.csv` directly for anything you intend to report |
| `run_manifest.txt` | Config path, alphas, `n_replicates`, `d`, container image, for provenance |

## Troubleshooting

If `condor_wait` exits with a nonzero status, a job was held or failed.
Check the printed `.log` path, and the corresponding `.out`/`.err` files
in `stage1_fit/`, then:

```bash
condor_q -hold
condor_q -better-analyze <job-id>
```

are the standard first steps for diagnosing why HTCondor won't run/finish
a job (common causes: a typo'd container image tag, or `request_disk` too
small for the pulled image — see `request_disk` in the config).

If the driver itself exits with "Expected fit output missing" during
aggregation, a fit job silently failed to produce its output file — check
that specific job's `stage1_fit/fit_N.err` for the underlying R error.
