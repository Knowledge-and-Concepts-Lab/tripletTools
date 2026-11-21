# Fit a group embedding at a fixed alpha with several random restarts

Fits `n_restarts` independent, randomly-initialized embeddings at a
fixed dimensionality `d` and Student-t/crowd-kernel shape `alpha`,
keeping whichever restart achieves the lowest test loss – the same
"several random seeds, keep the best" rule
[`run_group_embedding_from_list`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md)
uses, but at an arbitrary `alpha` rather than the crowd-kernel default
(\\\alpha = 1\\). This is the production "final-final" fit meant to run
*after*
[`estimate_group_alpha`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_group_alpha.md)
has already determined `alpha`, as the last step of
[`run_group_embedding_workflow`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_workflow.md)
– on data that has had the alpha-profiling sub-pool folded back into
training via
[`fold_alpha_test_to_train`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/fold_alpha_test_to_train.md),
since that sub-pool's only job (estimating `alpha`) is already done by
this point.

## Usage

``` r
fit_group_embedding_restarts_at_alpha(
  triplet_list,
  d,
  alpha,
  n_restarts = 5L,
  seed = 1L,
  max_epochs = 50000L,
  tolerance = 1e-04,
  tol_window = 10000L,
  device = NULL,
  norm_penalty = 0,
  verbose = TRUE
)
```

## Arguments

- triplet_list:

  A list of per-participant data frames, as returned by
  [`get.combined`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md),
  with a usable `sampleSet` column (see
  [`prepare_triplet_matrices`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/prepare_triplet_matrices.md)).

- d:

  Embedding dimensionality.

- alpha:

  The fixed Student-t/crowd-kernel shape parameter to fit under,
  typically `estimate_group_alpha(...)$alpha`.

- n_restarts:

  Number of independent random restarts. Default `5L`.

- seed:

  Base integer seed; restart `r` uses `seed + (r - 1) * 1000`, the same
  restart-seed formula used throughout this package's Condor workflows
  and
  [`run_group_embedding_workflow`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_workflow.md)'s
  own step 2.

- max_epochs, tolerance, tol_window, device, norm_penalty:

  Same meaning as the matching arguments of
  [`run_group_embedding_from_list`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md).

- verbose:

  Logical; print one progress line per restart. Default `TRUE`.

## Value

A named list:

- `embedding`:

  Numeric matrix, the winning restart's embedding (item names as row
  names, `dim_0`/`dim_1`/... columns).

- `loss`:

  That restart's test loss.

- `epoch`:

  Epoch at which that restart's training stopped.

- `history`:

  That restart's per-epoch training history.

- `restart`:

  Which restart (1-based) was kept.

- `restarts`:

  Data frame with one row per restart: `restart`, `seed`, `loss` – for
  inspecting the full spread, not just the winner.

## Details

Like
[`estimate_group_alpha`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_group_alpha.md),
this bypasses
[`train_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)'s
CKL-only (\\\alpha = 1\\) wrapper and calls the underlying
`_fit_offline()` Python entry point directly (`noise_model = "TSTE"`,
`module_kwargs = list(module__alpha = alpha)`). Restarts are
deliberately **not** warm-started from anything – the point of using
several random seeds is to search different local optima, which a shared
warm start would mostly defeat.

## Examples

``` r
if (FALSE) { # \dontrun{
grp <- run_group_embedding_from_list(icon_triplets, d = 3L)
joint <- estimate_group_alpha(icon_triplets, warm_start = grp$embedding)
folded <- fold_alpha_test_to_train(icon_triplets, joint$alpha_test_rows)
final_final <- fit_group_embedding_restarts_at_alpha(
  folded, d = 3L, alpha = joint$alpha, n_restarts = 5L
)
final_final$embedding
} # }
```
