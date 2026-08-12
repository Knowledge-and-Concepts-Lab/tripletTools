# Split a triplet matrix into a fitting subset and an internal-test subset

Randomly partitions the rows of `X_train` into two disjoint subsets: one
to actually fit an embedding on, and a smaller held-out `internal_test`
subset to evaluate it against during training (early stopping, and the
per-restart loss/accuracy that
[`estimate_dimensionality`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)/[`estimate_learning_curve`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_learning_curve.md)
use for model selection).

## Usage

``` r
sample_internal_test(X_train, frac, seed)
```

## Arguments

- X_train:

  Integer matrix of shape \\n \times 3\\ with columns `head`, `winner`,
  `loser` – typically the `X_train` element returned by
  [`prepare_triplet_matrices`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/prepare_triplet_matrices.md).

- frac:

  Proportion of `X_train`'s rows to hold out as `X_internal_test`. Must
  satisfy `0 < frac < 1`.

- seed:

  Integer seed controlling the random partition. Passing the same seed
  always returns the same split.

## Value

A named list with two elements:

- `X_fit`:

  Integer matrix with the same three columns as `X_train`, containing
  the rows to actually fit on.

- `X_internal_test`:

  Integer matrix with the same three columns, containing
  `floor(frac * nrow(X_train))` rows.

## Why "internal_test" and not "validation"

This is deliberately not called a validation set, because
`sampleAlg == "validation"` already names a different, unrelated concept
in this package's data model: a fixed, pre-specified probe set of
triplets used to measure inter-subject agreement (see
[`icon_triplets`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/icon_triplets.md),
`make_vmat`). "internal_test" is this function's own randomly-resampled,
per-restart hold-out, drawn from whatever `sampleSet == "train"` pool
[`prepare_triplet_matrices`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/prepare_triplet_matrices.md)
already isolated – it is unrelated to, and does not touch, either of
those.

## Examples

``` r
if (FALSE) { # \dontrun{
mats  <- prepare_triplet_matrices(icon_triplets, seed = 1L)
split <- sample_internal_test(mats$X_train, frac = 0.1, seed = 42L)
nrow(split$X_fit)
nrow(split$X_internal_test)
} # }
```
