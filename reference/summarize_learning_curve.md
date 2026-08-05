# Summarize per-restart learning-curve results

Aggregates a `results` data frame of one row per (fraction, restart) –
the same shape
[`estimate_learning_curve`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_learning_curve.md)
returns as its `results` element – into per-fraction summary statistics.
Exported for the same reason as
[`summarize_dimensionality`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/summarize_dimensionality.md):
so externally-collected results can be aggregated identically.

## Usage

``` r
summarize_learning_curve(results)
```

## Arguments

- results:

  Data frame with one row per (fraction, restart) and at least columns
  `fraction`, `n_train`, `loss`, `accuracy`, `norm_ratio`.

## Value

Data frame with one row per fraction and columns `fraction`, `n_train`,
`mean_loss`, `sd_loss`, `mean_accuracy`, `sd_accuracy`,
`mean_norm_ratio`, `max_norm_ratio` – see
[`estimate_learning_curve`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_learning_curve.md)'s
`summary` return element for what each column means.

## Examples

``` r
if (FALSE) { # \dontrun{
summarize_learning_curve(results)
} # }
```
