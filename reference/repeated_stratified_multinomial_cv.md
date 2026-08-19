# Repeated stratified cross-validated multinomial regression for embedding coordinates

Tests whether a categorical label with more than two levels can be
predicted from a set of embedding coordinates (or any numeric
predictors), using repeated stratified k-fold cross-validation with a
multinomial logistic regression model. Sibling function to
[`repeated_stratified_logistic_cv`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/repeated_stratified_logistic_cv.md),
which covers the 2-class case; see that function's documentation for the
shared repeated-CV design.

## Usage

``` r
repeated_stratified_multinomial_cv(
  X,
  y,
  repetitions = 100L,
  folds = 3L,
  seed = 12345,
  standardize = TRUE,
  maxit = 1000L,
  coefficient_warning = 10,
  probability_tolerance = 1e-08
)
```

## Arguments

- X:

  Numeric matrix or data frame of predictors, rows = items, columns =
  dimensions (e.g. embedding coordinates).

- y:

  Categorical outcome with 2 or more levels: a factor, character vector,
  or anything coercible via
  [`factor()`](https://rdrr.io/r/base/factor.html). For exactly 2
  levels,
  [`repeated_stratified_logistic_cv`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/repeated_stratified_logistic_cv.md)
  is usually a better fit – it fits a binomial model directly and
  reports positive-class-specific sensitivity/precision/F1 rather than
  the macro-averages this function always reports.

- repetitions:

  Number of times the full cross-validation is repeated with a fresh
  random fold assignment. Default `100L`.

- folds:

  Number of stratified folds per repetition. Default `3L`.

- seed:

  Integer random seed for reproducibility. Default `12345`.

- standardize:

  Logical. If `TRUE` (default), each predictor is centered and scaled
  using only the training fold's mean/SD before fitting, and the same
  transform is applied to the held-out fold.

- maxit:

  Maximum iterations passed to
  [`multinom`](https://rdrr.io/pkg/nnet/man/multinom.html). Default
  `1000L`; the underlying `nnet` default of `100` is often insufficient
  even for well-separated classes (see `diagnostics$converged`).

- coefficient_warning:

  Numeric threshold on the largest absolute fitted coefficient; fits
  exceeding this are flagged `large_coefficient` (a common symptom of
  quasi-complete separation). Default `10`.

- probability_tolerance:

  Numeric tolerance for counting predicted probabilities as numerically
  extreme (near 0 or 1). Default `1e-8`.

## Value

An object of class `"repetitioned_multinomial_cv"`: a named list with
elements:

- `performance`:

  Data frame with one row per repetition, giving pooled held-out
  macro-averaged metrics for that repetition (accuracy, balanced
  accuracy, precision, F1, AUC) plus a count of unstable folds.

- `summary`:

  Data frame with one row per metric, summarizing `performance` across
  repetitions (mean, SD, median, and 95\\ interval).

- `per_class_performance`:

  Data frame with one row per repetition x class, giving that class's
  one-vs-rest sensitivity, precision, F1, and AUC for that repetition.

- `per_class_summary`:

  Data frame with one row per class, summarizing `per_class_performance`
  across repetitions (mean, SD) – use this to see which specific classes
  are well- or poorly-predicted, information the macro-averaged metrics
  above collapse away.

- `diagnostics`:

  Data frame with one row per repetition x fold, recording fit
  convergence, coefficient size, and probability extremity, for
  identifying unstable fits.

- `predictions`:

  Data frame with one row per repetition x fold x item, giving the
  held-out predicted class and per-class predicted probabilities for
  every item in every repetition.

- `settings`:

  The arguments this call was made with, plus `n_items`, `n_dimensions`,
  `n_classes`, and `class_counts`.

## Details

Follows the same repeated stratified k-fold design as
[`repeated_stratified_logistic_cv`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/repeated_stratified_logistic_cv.md)
– see that function's *Details* – but fits
[`multinom`](https://rdrr.io/pkg/nnet/man/multinom.html) instead of
[`glm`](https://rdrr.io/r/stats/glm.html), predicts each held-out item's
class by the highest predicted probability (there is no single
`threshold` for more than two classes), and reports macro-averaged
(one-vs-rest per class, then mean across classes) metrics instead of
positive-class-specific ones. `balanced_accuracy` (macro-averaged
sensitivity/recall) and `sensitivity` are the same quantity in
[`repeated_stratified_logistic_cv`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/repeated_stratified_logistic_cv.md)'s
2-class output by construction; this function reports only
`balanced_accuracy` at the top level and keeps class-specific
sensitivity in `per_class_summary` instead of duplicating a
macro-averaged `sensitivity` column.

Each fold's fit is checked for signs of instability – non-convergence
within `maxit` iterations, non-finite or very large coefficients, or
held-out probabilities numerically indistinguishable from 0 or 1. Unlike
[`glm`](https://rdrr.io/r/stats/glm.html),
[`nnet::multinom`](https://rdrr.io/pkg/nnet/man/multinom.html) does not
reliably emit a distinct warning for quasi-complete separation, so these
numeric checks (rather than a captured warning message) carry the
diagnostic weight here – see `diagnostics$unstable_fit`.

## Examples

``` r
# Three partially-overlapping clusters in a 2D embedding. Deliberately not
# too cleanly separated -- classes separated enough to be classifiable but
# not perfectly, since near-perfect separation drives coefficients toward
# infinity and trips every fold's large_coefficient/unstable_fit flag
# (this is expected, quasi-complete-separation behavior, not a bug -- see
# the "unstable_fit" section above).
set.seed(1)
n <- 60
X <- rbind(
  cbind(rnorm(n / 3, mean = -1.5), rnorm(n / 3)),
  cbind(rnorm(n / 3, mean =  0),   rnorm(n / 3, mean = 1.5)),
  cbind(rnorm(n / 3, mean =  1.5), rnorm(n / 3))
)
y <- factor(rep(c("a", "b", "c"), each = n / 3))

cv_result <- repeated_stratified_multinomial_cv(
  X = X, y = y,
  repetitions = 5, folds = 3, seed = 1
)

# Mean performance and variability across repetitions
cv_result$summary
#>                              metric      mean         sd    median lower_2.5
#> accuracy                   accuracy 0.8200000 0.01394433 0.8166667 0.8016667
#> balanced_accuracy balanced_accuracy 0.8200000 0.01394433 0.8166667 0.8016667
#> precision                 precision 0.8202737 0.01352886 0.8187970 0.8015079
#> f1                               f1 0.8195260 0.01338999 0.8174067 0.8012518
#> auc                             auc 0.9316667 0.02515749 0.9437500 0.8922500
#>                   upper_97.5
#> accuracy           0.8333333
#> balanced_accuracy  0.8333333
#> precision          0.8337865
#> f1                 0.8325485
#> auc                0.9478750

# Which classes are best/worst predicted
cv_result$per_class_summary
#>   class  n mean_sensitivity sd_sensitivity mean_precision sd_precision
#> 1     a 20             0.87     0.02738613      0.8712281   0.03853232
#> 2     b 20             0.74     0.02236068      0.7642022   0.03222945
#> 3     c 20             0.85     0.05000000      0.8253907   0.02364313
#>     mean_f1      sd_f1 mean_auc     sd_auc
#> 1 0.8701814 0.02564241  0.94950 0.02541223
#> 2 0.7514022 0.01758953  0.88525 0.03865310
#> 3 0.8369946 0.03078694  0.96025 0.01341641
```
