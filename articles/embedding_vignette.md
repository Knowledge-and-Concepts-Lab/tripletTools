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
| [`run_group_embedding_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md) | Trains a single embedding on all participants’ data combined |
| [`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md) | Trains one embedding per participant plus a group embedding |

All three functions accept data in the named-list format used throughout
`tripletTools` (e.g. `icon_triplets`).

``` r

library(tripletTools)
```

------------------------------------------------------------------------

## Step 1: One-time Python environment setup

The embedding pipeline runs inside a self-contained conda environment.
You only need to do this once after installing the package. It installs
PyTorch, NumPy, pandas, scikit-learn, scipy, and skorch into an
environment called `"triplet-embeddings"`.

``` r

setup_python_env()
```

PyTorch is a large download (300–800 MB depending on your platform), so
the first run may take several minutes. On future R sessions you do
**not** need to call
[`setup_python_env()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/setup_python_env.md)
again — the environment is detected and activated automatically when you
load the package.

If conda is not found on your system,
[`setup_python_env()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/setup_python_env.md)
will stop with a message directing you to the Miniconda installation
page.

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
#>  $ individual:List of 5
#>   ..$ 3n7ggxph: num [1:32, 1:3] ...   # one matrix per participant
#>   ..$ b5wma4no: num [1:32, 1:3] ...
#>   ..$ d8mmm1qn: num [1:32, 1:3] ...
#>   ..$ jn7bbjc0: num [1:32, 1:3] ...
#>   ..$ pbby694o: num [1:32, 1:3] ...
#>  $ group     : num [1:32, 1:3] ...    # group embedding matrix
#>  $ history   :'data.frame': 6 obs. of 6 variables:
#>   ..$ worker_id              : chr [1:6] "3n7ggxph" ... "group"
#>   ..$ lowest_loss            : num [1:6] ...
#>   ..$ epoch                  : int [1:6] ...
#>   ..$ counter_from_last_update: int [1:6] ...
#>   ..$ n_train_triplets       : int [1:6] ...
#>   ..$ n_test_triplets        : int [1:6] ...
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
