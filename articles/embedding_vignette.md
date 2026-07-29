# Computing Triplet Embeddings

## Overview

This vignette explains how to compute similarity embeddings from triplet
judgment data collected with this package. Embeddings are computed by a
Python backend that uses PyTorch to optimize the crowd kernel (CKL)
noise model. From R you interact with this backend through three
functions:

| Function | What it does |
|----|----|
| [`setup_python_env()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/setup_python_env.md) | One-time installation of the Python environment |
| [`estimate_dimensionality()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md) | Fits embeddings across a range of dimensions to help choose `d` |
| [`run_group_embedding_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md) | Trains a single embedding on all participants’ data combined |
| [`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md) | Trains one embedding per participant plus a group embedding |

All functions accept data in the named-list format used throughout
`tripletTools` (e.g. `icon_triplets`).

``` r

library(tripletTools)
```

------------------------------------------------------------------------

## Step 1: One-time Python environment setup

The embedding pipeline runs inside a self-contained conda environment.
You only need to do this once after installing the package. It installs
PyTorch, NumPy, pandas, scikit-learn, scipy, skorch, and setuptools into
an environment called `"triplet-embeddings"`.

``` r

setup_python_env()
```

PyTorch is a large download (300–800 MB for a CPU build), so the first
run may take several minutes. On future R sessions you do **not** need
to call
[`setup_python_env()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/setup_python_env.md)
again — the environment is detected and activated automatically when you
load the package.

If conda is not found on your system,
[`setup_python_env()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/setup_python_env.md)
will stop with a message directing you to the Miniconda installation
page.

### If conda is installed but not found

On Windows, conda is sometimes installed without being added to the
system PATH, which means R cannot locate it automatically. If you see a
“Conda was not found” error despite having Miniconda or Anaconda
installed, find the conda executable and tell reticulate where it is:

``` r

# Common locations — run this to find yours:
possible_paths <- c(
  file.path(Sys.getenv("USERPROFILE"), "miniconda3", "Scripts", "conda.exe"),
  file.path(Sys.getenv("USERPROFILE"), "anaconda3", "Scripts", "conda.exe"),
  "C:/ProgramData/miniconda3/Scripts/conda.exe",
  "C:/ProgramData/anaconda3/Scripts/conda.exe",
  "C:/miniconda3/Scripts/conda.exe"
)
possible_paths[file.exists(possible_paths)]
```

Once you have the path, set it for the current session:

``` r

Sys.setenv(RETICULATE_CONDA = "C:/Users/you/miniconda3/Scripts/conda.exe")
```

To avoid having to do this every session, add the line to your
`.Renviron` file so it is set automatically on startup:

``` r

usethis::edit_r_environ()
# Add this line to the file that opens, then save and restart RStudio:
# RETICULATE_CONDA=C:/Users/you/miniconda3/Scripts/conda.exe
```

### GPU / CUDA support

If your machine has an NVIDIA GPU, you can install a CUDA-enabled build
of PyTorch by passing `cuda_version`. First check your maximum supported
CUDA version by running `nvidia-smi` in a terminal (look for “CUDA
Version” in the top-right corner), then pass any version at or below
that number:

``` r

setup_python_env(cuda_version = "12.4")  # common values: "11.8", "12.1", "12.4"
```

On Windows, CUDA libraries are bundled directly into the PyTorch build
from the pytorch conda channel, so the version number selects the
closest available build rather than an exact match. On Linux and macOS
the CUDA runtime is installed as a separate package from the nvidia
conda channel. CUDA-enabled builds are substantially larger (~1.5–2 GB).

------------------------------------------------------------------------

## Step 2: Computing a group embedding

[`run_group_embedding_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md)
pools the judgments from all participants and trains a single embedding
that captures the shared similarity structure across the group. This is
the fastest option and is a natural starting point before computing
individual embeddings.

``` r

grp <- run_group_embedding_from_list(
  triplet_list = icon_triplets,
  d            = 3L,       # number of dimensions
  max_epochs   = 50000L
)
```

The function prints training progress every 100 epochs, showing train
loss, test loss, train accuracy, and test accuracy. Training stops early
if the test loss has not improved meaningfully for 10,000 consecutive
epochs.

### What is returned

[`run_group_embedding_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md)
returns a named list:

``` r

str(grp)
#> List of 3
#>  $ embedding: num [1:32, 1:3] ...
#>   ..- attr(*, "dimnames")=List of 2
#>   .. ..$ : chr [1:32] "bdbwb" "bdbwb2" ...   # item names as row names
#>   .. ..$ : chr [1:3] "dim_0" "dim_1" "dim_2"
#>  $ loss     : num 0.412
#>  $ history  :'data.frame': 847 obs. of 5 variables:
#>   ..$ epoch     : int [1:847] 0 1 2 ...
#>   ..$ train_loss: num [1:847] ...
#>   ..$ test_loss : num [1:847] ...
#>   ..$ train_acc : num [1:847] ...
#>   ..$ test_acc  : num [1:847] ...
```

- `embedding` — a matrix with one row per stimulus (item names as row
  names) and `d` columns (`dim_0`, `dim_1`, …).
- `loss` — the best test loss achieved during training.
- `history` — a data frame recording train/test loss and accuracy at
  each epoch, useful for diagnosing convergence.

### Inspecting the result

``` r

# First few rows of the embedding
head(grp$embedding)

# Best test loss
cat("Best test loss:", round(grp$loss, 3), "\n")

# Did training converge? Plot the test loss curve.
plot(grp$history$epoch, grp$history$test_loss,
     type = "l", col = "steelblue",
     xlab = "Epoch", ylab = "Test loss",
     main = "Group embedding – training curve")
```

### Visualizing the embedding

Once you have the group embedding, you can use
[`plot_pics()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_pics.md)
to position stimulus images at their coordinates in the learned
similarity space (first two dimensions shown):

``` r

plot_pics(grp$embedding[, 1:2], icon_pics,
          psize = 0.04,
          xlab  = "Dimension 1",
          ylab  = "Dimension 2",
          main  = "Group embedding")
```

Items that appear close together were frequently judged as similar by
participants overall.

The group embedding can also be used with the full set of `tripletTools`
analysis functions. For example, to evaluate how well it predicts
held-out judgments for participant 1:

``` r

acc <- get.hoacc(grp$embedding, icon_triplets[[1]])
cat("Hold-out accuracy (participant 1):", round(acc, 3), "\n")
```

------------------------------------------------------------------------

## Step 3: Computing individual embeddings

[`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md)
trains a separate embedding for each participant and then trains an
additional group embedding on all participants’ data combined. This
takes longer but lets you study individual differences in how
participants represent the stimulus set.

``` r

results <- run_embeddings_from_list(
  triplet_list = icon_triplets,
  output_dir   = "embeddings_output",   # CSVs are also saved here
  d            = 3L,
  max_epochs   = 50000L
)
```

Output CSV files are written to `output_dir` as a side-effect:

| File | Contents |
|----|----|
| `embeddings.csv` | All per-participant and group embeddings concatenated |
| `embeddings_group.csv` | Group embedding only |
| `model_history.csv` | Training diagnostics for each participant and the group |

### What is returned

[`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md)
returns a named list:

``` r

str(results, max.level = 2)
#> List of 3
#>  $ individual:List of 6
#>   ..$ 3n7ggxph: num [1:32, 1:3] ...   # one matrix per participant
#>   ..$ b5wma4no: num [1:32, 1:3] ...
#>   ..$ d8mmm1qn: num [1:32, 1:3] ...
#>   ..$ jn7bbjc0: num [1:32, 1:3] ...
#>   ..$ pbby694o: num [1:32, 1:3] ...
#>   ..$ sc2xbd6w: num [1:32, 1:3] ...
#>  $ group     : num [1:32, 1:3] ...    # group embedding matrix
#>  $ history   :'data.frame': 7 obs. of 6 variables:
#>   ..$ worker_id              : chr [1:7] "3n7ggxph" ... "group"
#>   ..$ lowest_loss            : num [1:7] ...
#>   ..$ epoch                  : int [1:7] ...
#>   ..$ counter_from_last_update: int [1:7] ...
#>   ..$ n_train_triplets       : int [1:7] ...
#>   ..$ n_test_triplets        : int [1:7] ...
```

- `individual` — a named list of matrices, one per participant, in the
  same format as `grp$embedding` above. Element names match the
  `worker_id` labels in your data.
- `group` — a single matrix containing the group embedding.
- `history` — a data frame with one row per participant plus one row for
  the group, summarising training diagnostics.

### Inspecting training quality

The `history` data frame gives a quick overview of how well each
participant’s model converged:

``` r

results$history[, c("worker_id", "lowest_loss", "epoch", "n_train_triplets")]
```

Participants who stopped early (small `epoch`) and achieved a low
`lowest_loss` are well-modelled. If a participant’s `lowest_loss` is
much higher than the others, their data may be noisier or they may have
fewer trials.

### Working with individual embeddings

The individual embeddings are stored in `results$individual` and have
the same structure as the group embedding: a matrix with item row names
and columns `dim_0`, `dim_1`, …. This means they are compatible with all
existing `tripletTools` functions.

``` r

# Hold-out prediction accuracy for each participant using their own embedding
sapply(names(results$individual), function(wid) {
  get.hoacc(results$individual[[wid]], icon_triplets[[wid]])
})

# Prediction matrix: how well does each participant's embedding predict
# every other participant's held-out judgments?
pmat <- get.prediction.matrix(results$individual, icon_triplets)

# Do participants predict their own data better than others predict it?
cat("Mean self-prediction accuracy:  ", round(mean(diag(pmat)), 3), "\n")
cat("Mean other-prediction accuracy: ", round(mean(pmat[row(pmat) != col(pmat)]), 3), "\n")
```

### Visualizing individual embeddings

``` r

emb1 <- results$individual[[1]]

plot_pics(emb1[, 1:2], icon_pics,
          psize = 0.04,
          xlab  = "Dimension 1",
          ylab  = "Dimension 2",
          main  = paste("Individual embedding –", names(results$individual)[1]))
```

------------------------------------------------------------------------

## Choosing between the two functions

|  | [`run_group_embedding_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md) | [`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md) |
|----|----|----|
| **Speed** | Fast — one model | Slow — one model per participant + group |
| **Output** | Single group embedding | Per-participant + group embeddings |
| **Best for** | Quick summary of shared structure; pilot analyses | Studying individual differences; full analysis |
| **Saved files** | None | Three CSVs in `output_dir` |

If you only need the group embedding, prefer
[`run_group_embedding_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md).
If you want to study whether participants differ in their
representations — using tools like
[`get.prediction.matrix()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.prediction.matrix.md),
[`get.rep.dist()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md),
or
[`pacc.by.cluster()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/pacc.by.cluster.md)
— run
[`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md)
to obtain individual embeddings as well.

------------------------------------------------------------------------

## Controlling training

Both functions accept the same set of hyperparameters:

| Parameter | Default | Meaning |
|----|----|----|
| `d` | `5` | Number of embedding dimensions |
| `max_epochs` | `50000` | Maximum training epochs |
| `tolerance` | `1e-4` | Minimum loss improvement to reset the early-stopping counter |
| `tol_window` | `10000` | Epochs without improvement before stopping |
| `seed` | `222` | Random seed for reproducibility |

For exploratory analyses, the defaults are a reasonable starting point.
For a final analysis you may want to increase `max_epochs` and
`tol_window` to allow longer convergence, especially with large datasets
or high `d`.

To inspect the training curve after fitting:

``` r

plot(grp$history$epoch, grp$history$test_loss,
     type = "l", col = "steelblue", lwd = 2,
     xlab = "Epoch", ylab = "Test loss",
     main = "Convergence check")
lines(grp$history$epoch, grp$history$train_loss,
      col = "tomato", lwd = 2, lty = 2)
legend("topright",
       legend = c("Test", "Train"),
       col    = c("steelblue", "tomato"),
       lty    = c(1, 2), lwd = 2)
```

A well-converged model shows test loss flattening well before
`max_epochs`. If the loss is still falling at the end, increase
`max_epochs`.

------------------------------------------------------------------------

## Spherical embeddings

By default, embeddings are computed freely in Euclidean space — items
can end up anywhere in $`\mathbb{R}^d`$. Sometimes you have reason to
believe the true structure is instead **circular or spherical**: a
periodic variable like hue, phase, or time-of-day, where “wrapping
around” is part of the representation rather than an artifact to be fit
away.
[`train_embedding()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)
and every function built on it accept a `geometry` argument for exactly
this case.

``` r

grp_circle <- run_group_embedding_from_list(
  triplet_list = icon_triplets,
  d            = 2L,          # d = 2 means the *ambient* dimension —
  geometry     = "sphere",    # a 2-sphere embedded in R^2 is a circle
  radius       = 1,
  max_epochs   = 50000L
)
```

`d` always refers to the ambient dimension the sphere lives in, matching
the convention used everywhere else in the package. A circle is the
`d = 2` case; `d = 3` gives an ordinary sphere; higher `d` gives a
hypersphere. `radius` sets the sphere’s radius (default `1`) — mostly
cosmetic, since it just rescales the recovered coordinates.

### Why fitting takes two stages

Constraining every point to a sphere’s surface removes one degree of
freedom per item relative to a free Euclidean fit. That turns out to
matter a lot for optimization: starting from a random arrangement *on*
the sphere, gradient descent has too little room to maneuver and
reliably gets stuck reproducing close to chance-level accuracy, unable
to escape a bad ordering of the items around the sphere.

To avoid this, `geometry = "sphere"` fits in two stages automatically:

1.  A free Euclidean embedding is trained first (same `d`, same
    `max_epochs`/`tolerance`/`tol_window`), which easily finds a good
    arrangement because it isn’t constrained.
2.  That solution is projected onto the sphere and used as the starting
    point for a second fit, now constrained to stay on the sphere’s
    surface.

You’ll see both stages’ progress printed in the console, labelled
`[spherical warm start: fitting free Euclidean embedding]` and
`[fitting constrained spherical embedding]`. This roughly **doubles
training time** relative to `geometry = "euclidean"` — budget for it
when setting `max_epochs` for a spherical fit on a large dataset.

### Interpreting a circular (d = 2) embedding

For `d = 2`, each item’s angle around the circle is often more
interpretable than its raw `(x, y)` coordinates:

``` r

angles <- atan2(grp_circle$embedding[, 2], grp_circle$embedding[, 1])
names(angles) <- rownames(grp_circle$embedding)
sort(angles)
```

As with any embedding, the absolute rotation and reflection are
arbitrary (not identifiable from triplet judgments alone) — only the
relative circular *order* and *spacing* of items are meaningful.
Plotting the fit with an equal aspect ratio, together with the unit
circle for reference, makes this easy to check visually:

``` r

plot(grp_circle$embedding, asp = 1, pch = 19, col = "steelblue",
     xlab = "x", ylab = "y", main = "Circular group embedding")
theta <- seq(0, 2 * pi, length.out = 200)
lines(cos(theta), sin(theta), col = "gray70")
text(grp_circle$embedding, labels = rownames(grp_circle$embedding),
     pos = 3, cex = 0.7)
```

Points should fall almost exactly on the reference circle — the fit
constrains them there — but check that they aren’t all bunched together,
which would indicate the optimizer struggled even with the warm start
(try increasing `max_epochs`, or confirm the underlying structure is
actually close to circular in the first place).

### A worked example: recovering a known circular structure

To build intuition for what a good fit looks like, it helps to see the
recipe recover a *known* circular arrangement from synthetic data, since
with real data you don’t have ground truth to check against.

``` r

set.seed(0)
n_items <- 16
true_angle <- sort(runif(n_items, 0, 2 * pi))

# Triplet judgments generated purely from position on the circle
circ_dist <- function(i, j) {
  d <- abs(true_angle[i] - true_angle[j])
  pmin(d, 2 * pi - d)
}
n_triplets <- 4000
trip <- t(sapply(seq_len(n_triplets), function(k) {
  idx <- sample(seq_len(n_items), 3)
  h <- idx[1]; a <- idx[2]; b <- idx[3]
  if (circ_dist(h, a) < circ_dist(h, b)) c(h, a, b) - 1L else c(h, b, a) - 1L
}))
split <- floor(0.8 * n_triplets)

fit <- train_embedding(
  X_train = trip[1:split, ], X_test = trip[(split + 1):n_triplets, ],
  d = 2L, geometry = "sphere", max_epochs = 20000L, random_state = 0L
)

true_xy <- cbind(cos(true_angle), sin(true_angle))
aligned <- align.embeddings(list(true_xy, fit$embedding), scl = FALSE)
recovered_aligned <- aligned[[2]]

rmse <- sqrt(mean(rowSums((true_xy - recovered_aligned)^2)))
rmse
```

Comparing raw [`atan2()`](https://rdrr.io/r/base/Trig.html) angles (or
their ranks) between the true and recovered embeddings does *not* work
here: the recovered circle’s rotation and reflection are arbitrary, so
[`atan2()`](https://rdrr.io/r/base/Trig.html)’s wraparound point can
fall anywhere relative to the true item ordering, and a linear/rank
correlation between the two angle sequences can come out strongly
negative even when the circular structure was recovered correctly.
[`align.embeddings()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/align.embeddings.md)
avoids this by finding the rotation and reflection (and, if
`scl = TRUE`, scale) that best superimposes the two embeddings before
comparing them — the same approach the package uses to align embeddings
across participants. The RMS distance after alignment is close to `0`
for a good recovery; on a unit circle the largest possible distance
between two points is `2`.

### Combining with `estimate_dimensionality()`

[`estimate_dimensionality()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)
also accepts `geometry` and `radius`, so you can compare hold-out loss
for spherical vs. Euclidean fits at the same set of dimensions:

``` r

dim_est_sphere <- estimate_dimensionality(
  triplet_list = icon_triplets,
  dims         = 1:6,
  n_restarts   = 5L,
  geometry     = "sphere"
)
dim_est_sphere$summary
```

Comparing this against a `geometry = "euclidean"` run at the same `dims`
is a reasonable way to check whether constraining the data to a sphere
costs you meaningfully in hold-out accuracy — if it doesn’t, that’s
evidence the spherical structure is a genuine (or at least harmless)
description of the data rather than a misspecification.

------------------------------------------------------------------------

## Choosing the number of dimensions

The number of embedding dimensions `d` is a hyperparameter that must be
set before fitting. Too few dimensions underfit the similarity
structure; too many overfit noise. The right approach is to treat `d` as
an unknown, fit embeddings at several values, and choose the smallest
`d` whose hold-out loss is not meaningfully higher than the best.

Because the optimizer is stochastic, hold-out loss varies across runs at
the same `d`. A single fit per dimensionality is not reliable — a good
run at `d = 3` might beat a bad run at `d = 4` by chance.
[`estimate_dimensionality()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)
addresses this by fitting multiple independent random restarts at each
`d` and recording the best hold-out loss from each restart.

### Running the grid

``` r

dim_est <- estimate_dimensionality(
  triplet_list = icon_triplets,
  dims         = 1:8,       # dimensionalities to evaluate
  n_restarts   = 10L,       # independent random restarts per d
  max_epochs   = 50000L,
  seed         = 42L
)
```

Progress messages are printed as each restart completes. The function
returns a named list with two elements.

`$results` has one row per (dimension, restart):

``` r

head(dim_est$results)
#>   d restart      loss epoch
#> 1 1       1 0.6022...   ...
#> 2 1       2 0.6019...   ...
#> ...
```

`$summary` has one row per dimension, with the `best_d` flag identifying
the recommended choice:

``` r

dim_est$summary
#>   d mean_loss  min_loss    sd_loss best_d
#> 1 1    0.601     0.601     0.001   FALSE
#> 2 2    0.512     0.510     0.003   FALSE
#> 3 3    0.448     0.445     0.004    TRUE   # <-- recommended
#> 4 4    0.447     0.443     0.005   FALSE
#> ...
```

### How `best_d` is determined

The recommendation uses the **one-standard-error rule**: find the
dimensionality with the lowest mean hold-out loss, compute one standard
error of that mean (i.e. `sd_loss / sqrt(n_restarts)`), and then flag
the *smallest* `d` whose mean loss falls within that margin. This
favours parsimony — it selects the simplest model that is statistically
indistinguishable from the best.

### Visualizing the results

A simple plot shows mean loss by dimension with ±1 SD error bars. The
vertical dashed line marks the recommended `d`.

``` r

s <- dim_est$summary

plot(s$d, s$mean_loss,
     type = "b", pch = 19,
     xlab = "Dimensions (d)",
     ylab = "Mean test loss",
     main = "Hold-out loss by dimensionality")

arrows(s$d, s$mean_loss - s$sd_loss,
       s$d, s$mean_loss + s$sd_loss,
       angle = 90, code = 3, length = 0.05, col = "gray50")

abline(v = s$d[s$best_d], lty = 2, col = "steelblue")
```

Look for an **elbow**: a point where increasing `d` no longer reduces
loss substantially. The one-SE rule formalises this by returning the
smallest `d` in the flat region of the curve.

### Group vs. individual mode

By default (`group = TRUE`), all participants’ trials are pooled into a
single dataset and one dimensionality search is run on the combined
data. This is the right choice when you want to select a single `d` for
a group embedding, and it is faster because only one set of models is
trained.

``` r

# Default: pool all participants (group = TRUE is the default)
dim_est_grp <- estimate_dimensionality(
  triplet_list = icon_triplets,
  dims         = 1:6,
  n_restarts   = 10L
)
dim_est_grp$summary
```

If participants may differ substantially in representational complexity
— for example, if some participants produce clearly lower-dimensional
structure than others — you can run the search separately for each
participant with `group = FALSE`. In this mode the function returns a
named list, one element per participant, each with the same `results` /
`summary` structure.

``` r

dim_est_ind <- estimate_dimensionality(
  triplet_list = icon_triplets,
  dims         = 1:6,
  n_restarts   = 10L,
  group        = FALSE
)

# Result is a named list, one entry per participant
names(dim_est_ind)

# Recommended d for the first participant
dim_est_ind[[1]]$summary

# Extract the recommended d for every participant
sapply(dim_est_ind, function(x) x$summary$d[x$summary$best_d])
```

Item indices are rebuilt from each participant’s own trials in
individual mode, so the item space may differ across participants if not
everyone saw every stimulus.

### Practical notes

The function can be slow for large datasets or many restarts because it
trains `length(dims) × n_restarts` independent models (multiplied by the
number of participants in individual mode). A few suggestions:

- Start with a coarse grid (e.g. `dims = c(1, 2, 3, 5, 8)`) and
  `n_restarts = 5` to get a rough picture, then refine around the elbow.
- Use `max_epochs` and `tol_window` values consistent with the values
  you plan to use for the final embedding.
- If a GPU is available, pass `device = "cuda"` (or `"mps"` on Apple
  Silicon) to speed up each individual fit.
- Each (d, restart) pair is independent, so the function can be
  parallelised — see the next section.

------------------------------------------------------------------------

## Running in parallel

Because every (d, restart) fit is completely independent,
[`estimate_dimensionality()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)
can distribute work across multiple cores or a compute cluster with no
changes to your analysis code. Parallelism is controlled via the
[`future`](https://future.futureverse.org/) framework: you set a *plan*
once before calling the function, and the function uses however many
workers that plan provides.

Install the required packages once:

``` r

install.packages(c("future", "future.apply", "progressr"))
```

### Prerequisites for parallel execution

**The package must be installed, not just loaded with `load_all()`.**
Each worker is a fresh R process that loads `tripletTools` as a regular
package. If you are developing the package and have only run
`devtools::load_all()`, the workers will fail with “there is no package
called ‘tripletTools’”. Run `devtools::install()` first, then load the
package with
[`library(tripletTools)`](https://knowledge-and-concepts-lab.github.io/tripletTools/)
before setting up a parallel plan.

**Use `device = "cpu"` when running in parallel.** Multiple workers
simultaneously competing for a single GPU causes resource contention and
rarely speeds things up. Let the cores do the parallelism and leave GPU
acceleration for single-model fits.

**Progress monitoring.** Because worker output is not forwarded to the
main session, the `verbose` progress messages are suppressed
automatically. Install `progressr` to get a progress bar showing
completions instead. Wrap the call in
[`with_progress()`](https://progressr.futureverse.org/reference/with_progress.html)
— this is more reliable in RStudio than `handlers(global = TRUE)`, which
can fail if RStudio has already registered its own handlers:

``` r

library(progressr)

with_progress({
  dim_est <- estimate_dimensionality(...)
})
```

### Local multicore

Use all available cores on your workstation (or a subset):

``` r

library(future)
library(progressr)

# Pass the plan name as a string — the bare symbol form (plan(multisession))
# may not be found if future is loaded but not attached in all environments.
plan("multisession", workers = 4)   # or: workers = parallel::detectCores() - 1

with_progress({
  dim_est <- estimate_dimensionality(
    triplet_list = icon_triplets,
    dims         = 1:8,
    n_restarts   = 10L,
    max_epochs   = 50000L,
    seed         = 42L,
    device       = "cpu"   # use CPU in parallel — GPU contention rarely helps
  )
})

plan("sequential")   # restore serial execution when done
```

With 4 workers and 80 total fits (8 dims × 10 restarts), wall time drops
to roughly one quarter of the serial time.

`multisession` launches separate R processes, so it works on Windows,
macOS, and Linux. If you are on Linux or macOS and prefer lower
overhead, `plan("multicore")` uses forked processes instead. Note that
each worker initialises Python and the conda environment on startup, so
there is some fixed overhead before the first job completes and the
progress bar begins updating.

### HTCondor cluster

If you have access to an HTCondor cluster (e.g. UW–Madison’s CHTC),
install the `future.batchtools` package, which bridges `future` to
HTCondor’s job scheduler:

``` r

install.packages("future.batchtools")
```

You also need a one-time cluster template file that tells
`future.batchtools` how to construct HTCondor submit files for your
site. Save the following as `~/.batchtools.condor.tmpl` (adjust
`request_memory` and any site-specific lines for your cluster):

    universe     = vanilla
    executable   = '/opt/R/4.6.1/lib/R/bin/Rscript'
    arguments    = -e 'batchtools::doJobCollection("$(job.collection)")'

    transfer_input_files  = $(job.collection)
    should_transfer_files = YES
    when_to_transfer_output = ON_EXIT

    request_cpus   = 1
    request_memory = 4GB
    request_disk   = 2GB

    log    = $(log)
    output = $(output)
    error  = $(error)

    queue

Then submit your dimensionality search exactly as before, just with a
different plan:

``` r

library(future.batchtools)

plan(batchtools_condor, workers = 80)   # up to 80 simultaneous jobs

dim_est <- estimate_dimensionality(
  triplet_list = icon_triplets,
  dims         = 1:8,
  n_restarts   = 10L,
  max_epochs   = 50000L,
  seed         = 42L
)

plan(sequential)
```

`future.batchtools` handles job submission, monitors completion,
retrieves results, and assembles them — you get back the same `dim_est`
list as in the serial case.

**Prerequisite:** every worker node must have R, `tripletTools`, and the
`triplet-embeddings` conda environment already installed. This is a
one-time setup task; ask your cluster administrator or follow your
site’s software installation guide.

### An end-to-end Condor workflow

For the common case of “pick a dimension, check it against a learning
curve, and fit the best embedding,” `tripletTools` ships a driver script
that runs all three steps back to back, dispatching every individual fit
to HTCondor via `future.batchtools` as above:

    inst/condor/condor_workflow.R      # driver script
    inst/condor/condor_helpers.R       # small config-parsing helpers it sources
    inst/condor/condor.tmpl            # batchtools template: pre-installed execute nodes
    inst/condor/condor_apptainer.tmpl  # batchtools template: containerized (see below)
    inst/condor/params_template.yml    # template configuration file

Locate them with:

``` r

system.file("condor", package = "tripletTools")
```

**One-time setup**, on your CHTC submit node:

``` bash
cp $(Rscript -e 'cat(system.file("condor", "condor.tmpl", package = "tripletTools"))') \
   ~/.batchtools.condor.tmpl
# Adjust request_cpus/request_memory/request_disk defaults or add site-specific
# lines (e.g. a `requirements` clause) if needed -- see the comments in the
# template itself.
```

**Per run:**

1.  Save your triplet data as the named list of participant data frames
    these functions already expect (the same format
    [`get.combined()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md)
    returns and `icon_triplets` uses):

    ``` r

    saveRDS(icon_triplets, "triplet_data.rds")
    ```

2.  Copy `params_template.yml` and edit it for your run — the shipped
    copy documents every field inline:

    ``` bash
    cp $(Rscript -e 'cat(system.file("condor", "params_template.yml", package = "tripletTools"))') \
       my_params.yml
    ```

3.  Run the driver script. Since it only *orchestrates* — every actual
    embedding fit runs as its own Condor job — it’s safe to run directly
    on the submit node inside a persistent session
    (`screen`/`tmux`/`nohup`) rather than as a Condor job itself:

    ``` bash
    Rscript $(Rscript -e 'cat(system.file("condor", "condor_workflow.R", package = "tripletTools"))') \
      triplet_data.rds my_params.yml
    ```

This produces, in the `output_dir` set in `my_params.yml`:

| File | Contents |
|----|----|
| `dimensionality_results.csv` / `dimensionality_summary.csv` | [`estimate_dimensionality()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)’s `results`/`summary`, one Condor job per (dimension, restart) |
| `learning_curve_results.csv` / `learning_curve_summary.csv` | [`estimate_learning_curve()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_learning_curve.md)’s `results`/`summary`, at the `best_d` selected above, one Condor job per (fraction, restart) |
| `best_embedding.csv` | The final embedding, fit at `best_d` on the *full* dataset (item names in the `item` column) |
| `best_embedding_history.csv` | That final fit’s per-epoch training history (loss, accuracy, `norm_ratio`, …) |
| `run_manifest.txt` | Package version, input paths, `best_d`, and final loss, for provenance |

The final embedding is a dedicated fit rather than a reused fraction =
1.0 restart from the learning-curve stage:
[`estimate_learning_curve()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_learning_curve.md)
deliberately holds out the same test set at every fraction so hold-out
loss stays comparable across fractions, whereas the production embedding
should use ordinary train/test early stopping over *all* available data.

`seed`, `geometry`, `radius`, and `norm_penalty` in the config apply to
all three stages, so they describe one coherent embedding space
throughout; `max_epochs`/`tolerance`/`tol_window`/`device`/Condor
`resources` can be overridden per stage (e.g. a faster budget for the
dimensionality search, a more generous one for the final fit) — see the
comments in `params_template.yml`.

### Running in a container, instead of assuming pre-installed software

The setup above assumes R, `tripletTools`, and the `triplet-embeddings`
conda environment are already installed on whatever execute node
HTCondor matches each job to. If that isn’t true everywhere in your pool
— or you’d rather not depend on it — this repo also ships everything
needed to run each job inside a container instead, via Apptainer (which
CHTC’s execute nodes use to run Docker images directly, no separate
native build required):

    Dockerfile                                # builds the runtime image
    .github/workflows/docker-publish.yml      # builds + publishes it to ghcr.io on push
    inst/condor/condor_apptainer.tmpl         # batchtools template that uses the image

The image layers a base R install, Miniconda, the `triplet-embeddings`
conda environment (built via this package’s own
[`setup_python_env()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/setup_python_env.md),
so it’s created exactly the way a local install would be), and
`tripletTools` itself installed from GitHub. The GitHub Actions workflow
builds and pushes it to `ghcr.io/<org>/<repo>` automatically whenever
`Dockerfile`, `R/`, `inst/python/`, `inst/requirements.txt`, or
`DESCRIPTION` change on `main` — you don’t need Docker installed locally
to use it, only to debug a failing build.

To use it, point `condor:` at the container template instead in your
`params_template.yml` copy:

``` yaml
condor:
  template: ~/.batchtools.condor_apptainer.tmpl
  workers: 80
```

``` bash
cp $(Rscript -e 'cat(system.file("condor", "condor_apptainer.tmpl", package = "tripletTools"))') \
   ~/.batchtools.condor_apptainer.tmpl
```

`condor_apptainer.tmpl` uses HTCondor’s `container` universe with
`container_image = docker://ghcr.io/...`, the current general-purpose
mechanism for this as of this writing. This has **not** been validated
against a live HTCondor access point — if your access point rejects
`universe = container`, the template includes a commented-out fallback
using the older `+SingularityImage` classad; check CHTC’s current
container documentation, or ask CHTC support, for what your access point
expects.

### Checking the active plan

At any point you can confirm which plan is in effect:

``` r

library(future)
plan()   # prints a description of the current plan
```

`plan(sequential)` (the default) runs everything serially and requires
neither `future` nor `future.apply` — all other `tripletTools` functions
are unaffected.
