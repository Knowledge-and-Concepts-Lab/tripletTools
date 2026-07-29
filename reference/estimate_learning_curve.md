# Estimate a learning curve for a triplet embedding

Fits an embedding at a fixed dimensionality using increasing fractions
of the training data (10\\ every fit against the same fixed hold-out
set. Use the results to see how hold-out loss and accuracy improve as
more training data is added.

## Usage

``` r
estimate_learning_curve(
  triplet_list,
  d = 5L,
  by = 0.1,
  n_restarts = 10L,
  max_epochs = 50000L,
  tolerance = 1e-04,
  tol_window = 10000L,
  device = NULL,
  seed = 1L,
  verbose = TRUE,
  group = TRUE,
  norm_penalty = 0
)
```

## Arguments

- triplet_list:

  A named list of data frames, one per participant, as returned by
  [`get.combined`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md).
  Each data frame must contain columns `Center`, `Left`, `Right`,
  `Answer`, and `sampleSet`.

- d:

  Number of embedding dimensions to fit at every fraction. Default `5`.

- by:

  Granularity of the training-data fractions, as a proportion of the
  full training set. Default `0.1`, giving fractions
  `0.1, 0.2, ..., 1.0`. For example, `by = 0.25` gives
  `0.25, 0.5, 0.75, 1.0`.

- n_restarts:

  Number of independent random restarts per fraction. Default `10L`.
  More restarts give a more reliable estimate at each fraction but
  multiply compute time.

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

  Base integer seed for reproducibility. Controls both the initial
  shuffle that defines the nested training subsets and the per-restart
  initialization seeds. Default `1L`.

- verbose:

  Logical. If `TRUE` (default), print a progress line before each
  restart. Ignored when running in parallel (output from worker
  processes is not forwarded to the main session).

- group:

  Logical. If `TRUE` (default), pool all participants' trials and
  estimate a single learning curve on the combined data. If `FALSE`,
  estimate the learning curve independently for each participant and
  return a named list of result objects.

- norm_penalty:

  Non-negative number, forwarded to
  [`train_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)'s
  `norm_penalty` argument for every fit, controlling how each fit
  chooses its "best" training checkpoint. Default `0` preserves prior
  behavior exactly (checkpoints are chosen by raw test loss). See the
  *Diagnosing outlier items* section of
  [`train_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)
  for details.

## Value

When `group = TRUE` (the default), a named list with two elements:

- `results`:

  Data frame with one row per (fraction, restart) and columns
  `fraction`, `n_train`, `restart`, `loss`, `accuracy`, `epoch`,
  `norm_ratio`. `loss` and `accuracy` are the hold-out test loss and
  accuracy at the epoch of best test loss; `norm_ratio` is the ratio of
  the largest to median per-item embedding norm at that same epoch — see
  the *Diagnosing outlier items* section of
  [`train_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md).

- `summary`:

  Data frame with one row per fraction and columns `fraction`,
  `n_train`, `mean_loss`, `sd_loss`, `mean_accuracy`, `sd_accuracy`,
  `mean_norm_ratio`, `max_norm_ratio`. A rising `max_norm_ratio` across
  fractions alongside improving loss can mean the fit is relying more on
  an outlier item as more data comes in, rather than genuinely
  stabilizing.

When `group = FALSE`, a named list with one element per participant,
each of which has the same `results` / `summary` structure described
above.

## Group vs. individual mode

When `group = TRUE` (the default), all participants' trials are pooled
into a single dataset and one learning curve is estimated over the
combined data. This is appropriate when you want to know how a
group-level embedding's hold-out performance scales with data volume.

When `group = FALSE`, the learning curve is estimated independently for
each element of `triplet_list`, using only that participant's trials.
The return value is then a named list of result objects, one per
participant. Item indices are re-built from each participant's own data,
so the item space may differ across participants.

## Sampling scheme

The training pool is shuffled once (controlled by `seed`) and then
fractions are taken as nested, cumulative prefixes of that shuffled
order: the 20\\ on up to 100\\ amount of training data, not which trials
happened to be sampled. The hold-out set used for evaluation is the same
at every fraction and is never subsampled.

## Parallelism

By default the function runs serially. If the future.apply package is
installed, parallelism is controlled by setting a `future` plan before
calling this function. Each (fraction, restart) pair becomes an
independent future, so any backend supported by future works: local
multicore, SLURM, HTCondor, etc. In `group = FALSE` mode, futures are
still resolved at the (fraction, restart) level within each
participant's search, run one participant at a time.

If the progressr package is also installed, a progress bar is shown as
jobs complete. Enable it with `progressr::handlers(global = TRUE)`
before calling this function, or wrap the call in
`progressr::with_progress({ ... })`.

## Item indexing

All unique item names in `Center`, `Left`, and `Right` across all
participants are collected and sorted alphabetically; this sorted order
defines the zero-based integer indices passed to the Python model. In
`group = FALSE` mode, indexing is done separately for each participant
using only their own trials.

## Filtering

Trials with `NA` in the `sampleSet` column (attention-check trials) are
excluded before fitting. The `sampleSet` column (`"train"` / `"test"`)
defines the hold-out set. If no `sampleSet` column is present or all
values are `NA`, a 70/30 random train/test split is used instead.

## Examples

``` r
if (FALSE) { # \dontrun{
# Group mode (default): pool all participants
curve <- estimate_learning_curve(
  triplet_list = icon_triplets,
  d            = 3L,
  by           = 0.2,
  n_restarts   = 5L,
  max_epochs   = 20000L,
  seed         = 42L
)
curve$summary

# Individual mode: separate learning curve per participant
curve_ind <- estimate_learning_curve(
  triplet_list = icon_triplets,
  d            = 3L,
  by           = 0.2,
  n_restarts   = 5L,
  group        = FALSE
)
curve_ind[[1]]$summary

# Parallel: use 4 local cores (requires future.apply)
library(future)
plan(multisession, workers = 4)
curve <- estimate_learning_curve(icon_triplets, d = 3L, n_restarts = 10L)
plan(sequential)  # restore serial execution afterwards

# Plot hold-out loss vs. training set size
s <- curve$summary
plot(s$fraction, s$mean_loss, type = "b", pch = 19,
     xlab = "Fraction of training data", ylab = "Mean hold-out loss")

# Discourage outlier-chasing checkpoints during fitting itself
curve_penalized <- estimate_learning_curve(
  triplet_list = icon_triplets,
  d            = 3L,
  by           = 0.2,
  n_restarts   = 5L,
  norm_penalty = 0.05
)
} # }
```
