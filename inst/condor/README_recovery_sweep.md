# Deploying the choice-model recovery sweep on CHTC

This describes how to run `condor_recovery_sweep_workflow.py` from a CHTC
(or other HTCondor) submit node / access point. It answers a specific
question: when the choice model used to **fit** an embedding differs from
the choice model that actually **generated** the triplet judgments, how
much does recovery error suffer -- and how does that cost scale with how
far apart the two models are?

Unlike the other three Condor workflows in this directory, this one needs
**no input data file at all** -- it generates its own synthetic ground
truth and simulated triplets, then fits and scores every (generating
alpha, fitting alpha) pair.

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
  literal for the exact Gaussian limit. The number of fits is
  `len(alphas)^2`, so this is the main lever on total cost — the shipped
  default (8 values, 64 fits) was chosen after calibrating a single fit at
  ~46 minutes locally (CPU), i.e. ~49 hours of fitting work in total if
  run serially, which is exactly why this is worth spreading across
  Condor rather than running locally.
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

This first generates the ground-truth embedding and every generating
alpha's triplet set locally (fast — plain Python, no Condor job), then
submits one Condor job per (generating alpha, fitting alpha) pair (all of
them together, so HTCondor negotiates however many can run concurrently)
and blocks on `condor_wait` until every one finishes, then aggregates
every result locally. Since it only *orchestrates* the fit stage — all the
actual fitting happens as Condor jobs, not in this process — it's safe to
run directly on the access point inside a persistent session
(`screen`/`tmux`/`nohup`) rather than as a Condor job itself.

## Outputs

Written to `output_dir` (default `condor_recovery_sweep_output/`, set in
`my_params.yml`):

| File | Contents |
|---|---|
| `stage0_simulate/ground_truth.csv` | The synthetic ground-truth embedding (`item`, `dim_0`, `dim_1`, `dim_2`) |
| `stage0_simulate/triplets_gen<alpha>.csv` | Simulated triplets (`head`, `winner`, `loser`, 0-based) for each generating alpha |
| `stage1_fit/result_genNfitM.csv` | One (generating, fitting) pair's recovery error, loss, and stopping epoch |
| `results_long.csv` | Every pair's result, one row each (`gen_alpha`, `fit_alpha`, `recovery_error`, `loss`, `epoch`) |
| `error_matrix.csv` | The same data pivoted into a generating-alpha x fitting-alpha matrix of recovery errors — the diagonal is "matched model" recovery; off-diagonal cells show the cost of mismatch |
| `run_manifest.txt` | Config path, alphas, `d`, container image, for provenance |

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
