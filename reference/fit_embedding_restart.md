# Fit one embedding restart and summarize it as a single result row

Thin wrapper around
[`train_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)
that extracts the scalar summary values
[`estimate_dimensionality`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)
and
[`estimate_learning_curve`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_learning_curve.md)
each record per (dimension, restart) or (fraction, restart) job.
Exported so external tooling (e.g. a Condor per-job script running one
restart at a time on a cluster) can reproduce exactly the same
per-restart fitting logic as those two functions, rather than
re-deriving it.

## Usage

``` r
fit_embedding_restart(
  X_train,
  X_test,
  d,
  random_state,
  max_epochs,
  tolerance,
  tol_window,
  device,
  geometry,
  radius,
  norm_penalty
)
```

## Arguments

- X_train, X_test:

  See
  [`train_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md).

- d, max_epochs, tolerance, tol_window, device, geometry, radius,
  norm_penalty:

  Forwarded to
  [`train_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md).

- random_state:

  Forwarded to
  [`train_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)'s
  `random_state` argument, coerced to integer.

## Value

A one-row data frame with columns:

- `loss`:

  Best test loss achieved during training (identical to
  [`train_embedding()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)'s
  own `loss` return value).

- `accuracy`:

  Test accuracy at the epoch of best test loss.

- `epoch_stopped`:

  Epoch number at which training stopped
  ([`train_embedding()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)'s
  `epoch` return value) – the epoch convention
  [`estimate_dimensionality`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)
  records.

- `epoch_best`:

  Epoch number of the best test loss – the epoch convention
  [`estimate_learning_curve`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_learning_curve.md)
  records.

- `norm_ratio`:

  Ratio of the largest to median per-item embedding norm at the epoch of
  best test loss – see the *Diagnosing outlier items* section of
  [`train_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md).

## Examples

``` r
if (FALSE) { # \dontrun{
mats <- prepare_triplet_matrices(icon_triplets, seed = 1L)
fit_embedding_restart(
  X_train = mats$X_train, X_test = mats$X_test, d = 3L,
  random_state = 1L, max_epochs = 20000L, tolerance = 1e-4,
  tol_window = 10000L, device = NULL, geometry = "euclidean",
  radius = 1, norm_penalty = 0
)
} # }
```
