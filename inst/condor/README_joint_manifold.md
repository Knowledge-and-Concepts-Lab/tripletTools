# Deploying the joint geometry+choice-model manifold workflow on CHTC

This describes how to run `condor_joint_manifold_workflow.py` — the
Condor-scale version of the fully-rigorous joint manifold estimation
validated locally and documented in `vignette("condor_workflows_vignette")`.
It jointly estimates, for every participant, a position on a shared 1-D
latent manifold that determines **both** their own representational
geometry (a real re-fit embedding under their own current choice-model
shape, not just a kernel-weighted average of other participants' existing
fits) **and** their own choice-model shape parameter alpha.

**Only `mode: fit` is implemented so far** — one joint estimate across
every participant, no held-out validation. `mode: loo` (the full
leave-one-out validation used for the decisive local test this scales up)
is a planned follow-up.

## No R needed on the submit node -- same as the other three workflows

Every embedding refit (the expensive part — one real gradient-descent fit
per participant per outer iteration) runs inside the `tripletTools`
container via Condor. The per-iteration *update* step (re-aligning
embeddings, finding each participant's own best position, refitting the
shared population curve) **also runs as a Condor job in that same
container** — not a local Rscript call — specifically so this workflow
doesn't need R installed on the submit node at all (an earlier version of
this workflow ran that step locally; changed after finding that R isn't
always available, or installable without special permissions, on a real
submit node). This costs one extra submit/wait round-trip per outer
iteration, for a job that's cheap once it starts running (seconds) but
still pays ordinary Condor queueing/startup latency like any other job.

## Prerequisites (submit node)

- Python 3 + PyYAML (`pip install --user pyyaml`)
- HTCondor client tools (`condor_submit`, `condor_wait`, `condor_q`)

## Step 1: Get the workflow scripts

This workflow needs **three** files from this directory, not one or two —
easy to under-count by analogy with the simpler workflows here:

```bash
cp tripletTools/inst/condor/condor_joint_manifold_workflow.py .
cp tripletTools/inst/condor/condor_joint_manifold_fit.R .
cp tripletTools/inst/condor/condor_joint_manifold_update.R .
cp tripletTools/inst/condor/joint_manifold_params_template.yml ./my_params.yml
```

`condor_joint_manifold_fit.R` and `condor_joint_manifold_update.R` must
both live in the same directory as `condor_joint_manifold_workflow.py` —
the orchestrator locates each relative to its own file path.

## Step 2: Prepare your input files

**Two** files are needed (not one — this workflow needs real, already-fit
individual embeddings as a starting point, unlike the other workflows that
fit from raw triplets alone):

1. A combined triplet-judgment CSV (`worker_id`, `Center`, `Left`,
   `Right`, `Answer`, `sampleAlg`, `sampleSet` columns — the format
   `get.combined()` reads).
2. A combined individual-embeddings CSV (`worker_id`, `item`, `dim_0`,
   `dim_1`, … — the format `get.combined(..., eflag = TRUE)` reads), one
   embedding per participant, all sharing the same dimensionality and item
   set. This is exactly `run_embeddings_from_list()`'s per-individual
   output, or the Condor-scale equivalent from
   `condor_individual_embeddings_workflow.py`.

Only participants present in **both** files are used; the workflow prints
a note if some `worker_id`s were only in one of the two.

## Step 3: Edit the config

Open `my_params.yml` and set at minimum:

- `d` — must match `embeddings.csv`'s own dimensionality (the workflow
  refits starting from each participant's existing fit, so it can't change
  `d` partway through).
- `n_outer` — number of alternating iterations. Local (serial) validation
  was capped at 2-4 for a runnable turnaround; since Condor removes that
  wall-clock constraint, 6-8 is a more reasonable default here.
- `condor.container_image` / `condor.resources` / `condor.batch_size` —
  same meaning as the other workflows in this directory; see the comments
  in `joint_manifold_params_template.yml`.
- `max_epochs` / `tolerance` / `tol_window` — applied to every embedding
  refit, every iteration. Each refit is warm-started from the
  participant's current embedding, so later iterations typically converge
  much faster than the first.

## Step 4: Deploy

```bash
python3 condor_joint_manifold_workflow.py triplet_data.csv embeddings.csv my_params.yml
```

This runs `n_outer` sequential rounds, each submitting **one Condor batch
covering every participant's refit at once** (not one batch per
participant per iteration — see the orchestrator's own docstring for why
this matters for how many submission rounds the whole run actually pays
the Condor queueing/startup latency for), followed by one single-job
Condor batch for that iteration's update step. Safe to run directly on
the access point inside a persistent session (`screen`/`tmux`/`nohup`),
same as the other workflows here — it only *orchestrates*, every actual
computation runs as a Condor job.

Expect this to take a while: at `n=24` participants and `n_outer=6`, the
embedding-refit batches alone involve ~144 real embedding fits, each
potentially taking several minutes depending on `max_epochs`/warm-start
quality. The whole point of running this on Condor rather than locally is
that those ~24 refits *within* a single iteration happen in parallel
rather than one at a time — see the decisive local test in
`vignette("condor_workflows_vignette")` for the serial timing this is
meant to improve on.

## Outputs

Written to `output_dir` (default `condor_joint_manifold_output/`, set in
`my_params.yml`):

| File | Contents |
|---|---|
| `setup/` | Per-participant original embeddings, pre-indexed train/test/pooled triplet files -- built once, reused every iteration |
| `iterN/refit/embeddings/personI.csv` | Participant I's refit embedding after outer iteration N |
| `iterN/update.out`, `iterN/update.err` | That iteration's update-step Condor job log/error output |
| `iterN/positions.csv`, `iterN/beta.csv` | That iteration's updated manifold positions and population-curve (beta0, beta1, bandwidth) |
| `iterN/aligned/personI.csv` | GPA-aligned embeddings used internally for that iteration's position search |
| `final_embeddings.csv` | Every participant's FINAL (last-iteration) refit embedding, indexed by `worker_id` and `item` |
| `final_positions.csv` | Every participant's final manifold position, indexed by `worker_id` |
| `run_manifest.txt` | Participant count, `d`, `n_outer`, final beta0/beta1, container image, for provenance |

## Troubleshooting

If `condor_wait` exits with a nonzero status during an embedding-refit
batch, a job was held or failed — same first steps as the other workflows
here (`condor_q -hold`, `condor_q -better-analyze <job-id>`), and check
that iteration's `iterN/refit/refit_*.err` files.

If `condor_wait` exits with a nonzero status during an update-step batch,
or the driver exits with "did not produce expected output," check that
iteration's `iterN/update.err` for the underlying R error (same
diagnosis steps as an embedding-refit failure, just for the single update
job instead of the batch of per-participant ones).

## Resuming / extending a run

Rerunning the exact same command, pointing at the same `output_dir`,
**automatically resumes** after the last fully-completed iteration rather
than starting over — it scans `iter1/`, `iter2/`, ... for the first
incomplete or missing one and continues from there, using that state's
positions/beta0/beta1 and refit embeddings as the starting point. This
also means **raising `n_outer` in the config and rerunning is how you
extend a run** that turned out to need more iterations than you first
asked for (`n_outer` is a total iteration count, not "run this many
more") — useful if the population curve hasn't settled yet (watch
whether beta0/beta1 are still moving by the last iteration, and whether
any small subgroup of participants is still steadily drifting in
position rather than having stabilized).

Resuming is refused, with a clear error, if the current `triplet_data.csv`/
`embeddings.csv` would produce a different participant list or item order
than the run that's being resumed — a silent mismatch there would
misattribute every position/embedding to the wrong person rather than
fail loudly. Pass `--fresh` to ignore any existing `iter*/` state and
start over from iteration 1 in the same `output_dir` regardless.

`mode: loo` remains a planned follow-up, not yet built.
