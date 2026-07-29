# Estimate the latent dimensionality of a triplet dataset

Fits embeddings across a range of dimensionalities, each with multiple
random restarts, and returns the hold-out loss at every (dimension,
restart) combination. Use the results to select the smallest
dimensionality that achieves near-minimum hold-out loss.

## Usage

``` r
estimate_dimensionality(
  triplet_list,
  dims = 1:8,
  n_restarts = 10L,
  max_epochs = 50000L,
  tolerance = 1e-04,
  tol_window = 10000L,
  device = NULL,
  seed = 1L,
  verbose = TRUE,
  group = TRUE,
  geometry = c("euclidean", "sphere"),
  radius = 1,
  norm_penalty = 0,
  best_d_norm_penalty = 0
)
```

## Arguments

- triplet_list:

  A named list of data frames, one per participant, as returned by
  [`get.combined`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md).
  Each data frame must contain columns `Center`, `Left`, `Right`,
  `Answer`, and `sampleSet`.

- dims:

  Integer vector of dimensionalities to evaluate. Default `1:8`.

- n_restarts:

  Number of independent random restarts per dimensionality. Default
  `10L`. More restarts give a more reliable loss estimate but multiply
  compute time.

- max_epochs:

  Maximum training epochs per restart. Default `50000L`.

- tolerance:

  Loss tolerance for early stopping. Default `1e-4`.

- tol_window:

  Epochs without meaningful improvement before early stopping triggers.
  Default `10000L`.

- device:

  PyTorch device string, or `NULL` (default) to auto-select: CUDA GPU if
  available, then Apple MPS, then CPU.

- seed:

  Base integer seed for reproducibility. Each (d, restart) pair receives
  a unique derived seed so all runs are independently replicable.
  Default `1L`.

- verbose:

  Logical. If `TRUE` (default), print a progress line before each
  restart. Ignored when running in parallel (output from worker
  processes is not forwarded to the main session).

- group:

  Logical. If `TRUE` (default), pool all participants' trials and run a
  single dimensionality search on the combined data. If `FALSE`, run the
  search independently for each participant and return a named list of
  result objects.

- geometry:

  Either `"euclidean"` (default) or `"sphere"`. When `"sphere"`, each
  restart embeds items onto the surface of a `d`-dimensional sphere of
  radius `radius` (`d = 2` is a circle) instead of freely in \\R^d\\.
  See the *Spherical embeddings* section of
  [`train_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)
  for details, including why this roughly doubles compute time per
  restart. Dimensions in `dims` still refer to the ambient dimension of
  the sphere (its surface itself has one fewer degree of freedom), so
  results stay directly comparable to a `geometry = "euclidean"` search
  over the same `dims`.

- radius:

  Radius of the sphere used when `geometry = "sphere"`. Ignored when
  `geometry = "euclidean"`. Default `1`.

- norm_penalty:

  Non-negative number, forwarded to
  [`train_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)'s
  `norm_penalty` argument for every restart, controlling how each
  individual fit chooses its "best" training checkpoint. Default `0`
  preserves prior behavior exactly (checkpoints are chosen by raw test
  loss). This changes the actual fitted embeddings and the
  `loss`/`norm_ratio` values reported in `results`; it is independent of
  `best_d_norm_penalty` below, which only affects *which already-fitted
  dimension* gets flagged `best_d`. See the *Diagnosing outlier items*
  section of
  [`train_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)
  for details.

- best_d_norm_penalty:

  Non-negative number controlling how much `best_d` selection penalizes
  dimensions whose fits show outlier items (see `norm_ratio` in the
  *Diagnosing outlier items* section of
  [`train_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)).
  `best_d` is chosen by applying the same one-standard-error rule
  described below to
  `penalized_loss = mean_loss + best_d_norm_penalty * (max_norm_ratio - 1)`
  instead of `mean_loss` directly. Default `0` leaves selection based
  purely on `mean_loss`, matching prior behavior; increase it to make
  dimensions with a high `max_norm_ratio` less likely to be selected as
  `best_d` even if their mean loss is lowest. This is a purely post-hoc
  selection rule applied to already- fitted results —
  `results`/`summary` always report the raw, unpenalized
  `loss`/`mean_loss` regardless of this setting, and it does not affect
  fitting itself (see `norm_penalty` above for that).

## Value

When `group = TRUE` (the default), a named list with two elements:

- `results`:

  Data frame with one row per (dimension, restart) and columns `d`,
  `restart`, `loss`, `accuracy`, `epoch`, `norm_ratio`. `loss` and
  `accuracy` are the hold-out test loss and accuracy at the epoch of
  best test loss. `norm_ratio` is the ratio of the largest to median
  per-item embedding norm at that same epoch — see the *Diagnosing
  outlier items* section of
  [`train_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md).
  `norm_ratio` is only meaningful for `geometry = "euclidean"`; always
  `~1` under `geometry = "sphere"`.

- `summary`:

  Data frame with one row per dimension and columns `d`, `mean_loss`,
  `min_loss`, `sd_loss`, `mean_accuracy`, `sd_accuracy`,
  `mean_norm_ratio`, `max_norm_ratio`, `penalized_loss`.
  `penalized_loss` equals `mean_loss` whenever `best_d_norm_penalty = 0`
  (the default) — see the `best_d_norm_penalty` argument. The logical
  column `best_d` marks the smallest `d` within one standard error of
  the global minimum `penalized_loss`. A `d` with low `mean_loss` but a
  high `max_norm_ratio` relative to smaller dimensions is a sign that
  the loss improvement may be coming from an outlier item being pushed
  away rather than genuinely better structure.

When `group = FALSE`, a named list with one element per participant,
each of which has the same `results` / `summary` structure described
above.

## Group vs. individual mode

When `group = TRUE` (the default), all participants' trials are pooled
into a single dataset and one dimensionality search is performed over
the combined data. This is appropriate when you want to select a single
embedding dimensionality for a group embedding.

When `group = FALSE`, the search is run independently for each element
of `triplet_list`, using only that participant's trials. The return
value is then a named list of result objects, one per participant. Item
indices are re-built from each participant's own data, so the item space
may differ across participants.

## Parallelism

By default the function runs serially. If the future.apply package is
installed, parallelism is controlled by setting a `future` plan before
calling this function. Each (d, restart) pair becomes an independent
future, so any backend supported by future works: local multicore,
SLURM, HTCondor, etc. See the "Computing Triplet Embeddings" vignette
for worked examples.

If the progressr package is also installed, a progress bar is shown as
jobs complete. Enable it with `progressr::handlers(global = TRUE)`
before calling this function, or wrap the call in
`progressr::with_progress({ ... })`. Progress reporting works in both
serial and parallel modes.

## Method

For each value of `d` in `dims` and each restart, an independent
embedding is trained from a fresh random initialisation (controlled by a
deterministic seed derived from `seed`, `d`, and the restart index). The
best test loss achieved during training is recorded.

The `summary` element of the return value includes a `best_d` column
that applies the one-standard-error rule to the per-dimension mean loss:
the smallest `d` whose mean loss is within one standard error of the
global minimum mean loss is flagged as `best_d = TRUE`. This tends to
favour parsimony when several dimensions achieve similar loss.

## Item indexing

All unique item names in `Center`, `Left`, and `Right` across all
participants are collected and sorted alphabetically; this sorted order
defines the zero-based integer indices passed to the Python model. In
`group = FALSE` mode, indexing is done separately for each participant
using only their own trials.

## Filtering

Trials with `NA` in the `sampleSet` column (attention-check trials) are
excluded before fitting. The `sampleSet` column (`"train"` / `"test"`)
is used to split data for early stopping. If no `sampleSet` column is
present or all values are `NA`, a 70/30 random train/test split is used
instead.

## Examples

``` r
if (FALSE) { # \dontrun{
# Group mode (default): pool all participants
dim_est <- estimate_dimensionality(
  triplet_list = icon_triplets,
  dims         = 1:6,
  n_restarts   = 5L,
  max_epochs   = 20000L,
  seed         = 42L
)
dim_est$summary

# Individual mode: separate search per participant
dim_est_ind <- estimate_dimensionality(
  triplet_list = icon_triplets,
  dims         = 1:6,
  n_restarts   = 5L,
  group        = FALSE
)
# Best dimensionality for the first participant:
dim_est_ind[[1]]$summary

# Penalize dimensions whose fits show a strong outlier item when
# choosing best_d, rather than selecting on raw mean loss alone
# (post-hoc selection only -- does not change the fits themselves)
dim_est_penalized <- estimate_dimensionality(
  triplet_list      = icon_triplets,
  dims              = 1:6,
  n_restarts        = 5L,
  best_d_norm_penalty = 0.05
)
dim_est_penalized$summary[, c("d", "mean_loss", "max_norm_ratio",
                               "penalized_loss", "best_d")]

# Discourage outlier-chasing checkpoints during fitting itself, at every
# dimension/restart (changes the fits and reported loss/norm_ratio)
dim_est_fit_penalized <- estimate_dimensionality(
  triplet_list = icon_triplets,
  dims         = 1:6,
  n_restarts   = 5L,
  norm_penalty = 0.05
)

# Parallel: use 4 local cores (requires future.apply)
library(future)
plan(multisession, workers = 4)
dim_est <- estimate_dimensionality(icon_triplets, dims = 1:6, n_restarts = 10L)
plan(sequential)  # restore serial execution afterwards

# Plot mean loss +/- 1 SD by dimension
s <- dim_est$summary
plot(s$d, s$mean_loss, type = "b", pch = 19,
     xlab = "Dimensions", ylab = "Mean test loss")
arrows(s$d, s$mean_loss - s$sd_loss, s$d, s$mean_loss + s$sd_loss,
       angle = 90, code = 3, length = 0.05)
abline(v = s$d[s$best_d], lty = 2)

# Compare loss, accuracy, and norm_ratio side by side across dimensions
s[, c("d", "mean_loss", "mean_accuracy", "mean_norm_ratio", "max_norm_ratio")]
} # }
```
