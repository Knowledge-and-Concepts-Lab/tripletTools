# Plot prediction accuracy as a function of model strength

A calibration/psychometric-function style plot of how often a model's
predicted winner matches the actual (e.g. human) choice, as a function
of a continuous measure of how "easy" the triplet should be – typically
[`model.strength()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/model.strength.md)'s
distance-ratio metric, or (when
[`model.strength()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/model.strength.md)
is called with its own `alpha` argument set) the choice-model
probability of the predicted winner. Shows the raw per-triplet outcomes,
Wilson-score binned accuracy with confidence intervals, and (optionally)
a fitted binomial GLM curve, all on one plot.

## Usage

``` r
plot_accuracy_vs_strength(
  strength,
  accuracy,
  n_bins = 10,
  binning = c("quantile", "equal_width"),
  ci_level = 0.95,
  glm = TRUE,
  show_raw = TRUE,
  xlab = "Model strength",
  ylab = "P(correct)",
  main = NULL,
  ...
)
```

## Arguments

- strength:

  Numeric vector giving each triplet's model-strength value (e.g. the
  output of
  [`model.strength()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/model.strength.md)).

- accuracy:

  Vector the same length as `strength`: 1/`TRUE` if the model's
  predicted winner matched the actual choice on that triplet, 0/`FALSE`
  otherwise.

- n_bins:

  Number of bins along the strength axis (default 10). See `binning`.

- binning:

  `"quantile"` (default) puts roughly equal numbers of triplets in each
  bin, which keeps a bin's point from being a sparse-data artifact even
  when `strength` values cluster (e.g. most triplets near 1.0 for a good
  embedding). `"equal_width"` instead divides the observed range of
  `strength` into `n_bins` equal-width bins – more interpretable x-axis
  spacing, at the cost of some bins potentially having very few or no
  points.

- ci_level:

  Confidence level for each bin's Wilson score interval (default 0.95).

- glm:

  Logical; if `TRUE` (default), fits `accuracy ~ strength` as a binomial
  GLM and overlays its predicted curve.

- show_raw:

  Logical; if `TRUE` (default), plots the raw 0/1 outcomes, jittered
  vertically, as a light background layer so the binned summary isn't
  the only thing shown.

- xlab, ylab, main, ...:

  Passed to the underlying
  [`plot()`](https://rdrr.io/r/graphics/plot.default.html) call.

## Value

Invisibly, a list with `bins` (the per-bin summary data frame:
`strength`, `n`, `n_correct`, `p_correct`, `ci_lower`, `ci_upper`) and
`glm_fit` (the fitted `glm` object, or `NULL` if `glm = FALSE`).

## Details

Binned proportions use the Wilson score interval rather than a naive
`phat +/- 1.96*SE` interval, since the latter can extend outside \[0,
1\] or be badly too narrow exactly where this plot is most informative:
bins near `strength = 1` where the model should rarely be wrong, so the
observed proportion of errors in that bin is small and its naive SE is
an unreliable guide to the uncertainty.

## Examples

``` r
set.seed(1)
n <- 300
strength <- runif(n, 0.5, 1)
# Simulated probability of a correct prediction that increases with
# strength, for a plausible example.
p_true <- 0.5 + 0.45 * (strength - 0.5) / 0.5
accuracy <- rbinom(n, 1, p_true)

plot_accuracy_vs_strength(strength, accuracy)
```
