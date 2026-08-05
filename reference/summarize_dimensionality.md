# Summarize per-restart dimensionality-search results

Aggregates a `results` data frame of one row per (dimension, restart) –
the same shape
[`estimate_dimensionality`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)
returns as its `results` element – into per-dimension summary statistics
and a `best_d` selection. Exported so results collected from elsewhere
(e.g. a Condor-distributed run whose per-restart fits ran via
[`fit_embedding_restart`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/fit_embedding_restart.md))
can be aggregated with exactly the same logic
[`estimate_dimensionality()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)
uses internally.

## Usage

``` r
summarize_dimensionality(results, n_restarts, best_d_norm_penalty = 0)
```

## Arguments

- results:

  Data frame with one row per (dimension, restart) and at least columns
  `d`, `loss`, `accuracy`, `norm_ratio`.

- n_restarts:

  Number of restarts per dimension (assumed constant across dimensions,
  matching
  [`estimate_dimensionality`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)'s
  own assumption), used for the standard-error term in `best_d`
  selection.

- best_d_norm_penalty:

  Non-negative number; see
  [`estimate_dimensionality`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)'s
  argument of the same name. Default `0` (post-hoc selection based on
  raw `mean_loss`).

## Value

Data frame with one row per dimension and columns `d`, `mean_loss`,
`min_loss`, `sd_loss`, `mean_accuracy`, `sd_accuracy`,
`mean_norm_ratio`, `max_norm_ratio`, `penalized_loss`, `best_d` – see
[`estimate_dimensionality`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)'s
`summary` return element for what each column means.

## Examples

``` r
if (FALSE) { # \dontrun{
# results collected from separately-run restarts, e.g. from Condor jobs
summarize_dimensionality(results, n_restarts = 10L)
} # }
```
