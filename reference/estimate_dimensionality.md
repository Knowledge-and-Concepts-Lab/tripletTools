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
  verbose = TRUE
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

## Value

A named list with two elements:

- `results`:

  Data frame with one row per (dimension, restart) and columns `d`,
  `restart`, `loss`, `epoch`.

- `summary`:

  Data frame with one row per dimension and columns `d`, `mean_loss`,
  `min_loss`, `sd_loss`. The logical column `best_d` marks the smallest
  `d` within one standard error of the global minimum mean loss.

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
defines the zero-based integer indices passed to the Python model.

## Filtering

Trials with `NA` in the `sampleSet` column (attention-check trials) are
excluded before fitting. The `sampleSet` column (`"train"` / `"test"`)
is used to split data for early stopping. If no `sampleSet` column is
present or all values are `NA`, a 70/30 random train/test split is used
instead.

## Examples

``` r
if (FALSE) { # \dontrun{
# Serial (default)
dim_est <- estimate_dimensionality(
  triplet_list = icon_triplets,
  dims         = 1:6,
  n_restarts   = 5L,
  max_epochs   = 20000L,
  seed         = 42L
)

# Parallel: use 4 local cores (requires future.apply)
library(future)
plan(multisession, workers = 4)
dim_est <- estimate_dimensionality(icon_triplets, dims = 1:6, n_restarts = 10L)
plan(sequential)  # restore serial execution afterwards

# Summary with recommended dimensionality flagged
dim_est$summary

# Plot mean loss +/- 1 SD by dimension
s <- dim_est$summary
plot(s$d, s$mean_loss, type = "b", pch = 19,
     xlab = "Dimensions", ylab = "Mean test loss")
arrows(s$d, s$mean_loss - s$sd_loss, s$d, s$mean_loss + s$sd_loss,
       angle = 90, code = 3, length = 0.05)
abline(v = s$d[s$best_d], lty = 2)
} # }
```
