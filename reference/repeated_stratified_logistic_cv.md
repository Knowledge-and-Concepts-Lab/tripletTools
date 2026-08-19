# Repeated stratified cross-validated logistic regression for embedding coordinates

Tests whether a binary category label can be predicted from a set of
embedding coordinates (or any numeric predictors), using repeated
stratified k-fold cross-validation with a logistic regression model.

## Usage

``` r
repeated_stratified_logistic_cv(
  X,
  y,
  repetitions = 100L,
  folds = 3L,
  seed = 12345,
  standardize = TRUE,
  threshold = 0.5,
  coefficient_warning = 10,
  probability_tolerance = 1e-08
)
```

## Arguments

- X:

  Numeric matrix or data frame of predictors, rows = items, columns =
  dimensions (e.g. embedding coordinates).

- y:

  Binary outcome: coded `0`/`1`, `FALSE`/`TRUE`, or a two-level
  factor/character vector. Must have the same length as `nrow(X)`.

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

- threshold:

  Probability threshold used to convert predicted probabilities into
  class predictions. Default `0.5`.

- coefficient_warning:

  Numeric threshold on the largest absolute logistic-regression
  coefficient; fits exceeding this are flagged `large_coefficient` (a
  common symptom of quasi-complete separation). Default `10`.

- probability_tolerance:

  Numeric tolerance for counting predicted probabilities as numerically
  extreme (near 0 or 1). Default `1e-8`.

## Value

An object of class `"repetitioned_logistic_cv"`: a named list with
elements:

- `performance`:

  Data frame with one row per repetition, giving pooled held-out
  performance metrics for that repetition (accuracy, balanced accuracy,
  sensitivity, specificity, precision, F1, AUC) plus a count of unstable
  folds.

- `summary`:

  Data frame with one row per metric, summarizing `performance` across
  repetitions (mean, SD, median, and 95\\ interval).

- `diagnostics`:

  Data frame with one row per repetition x fold, recording fit
  convergence, coefficient size, and separation warnings, for
  identifying unstable fits.

- `predictions`:

  Data frame with one row per repetition x fold x item, giving the
  held-out predicted probability and class for every item in every
  repetition.

- `settings`:

  The arguments this call was made with, plus `n_items`, `n_dimensions`,
  `n_positive`, and `n_negative`.

## Details

In each repetition, observations are split into `folds` stratified folds
(class proportions preserved within each fold), and a logistic
regression is fit on all but one fold and evaluated on the held-out
fold, cycling through every fold. Held-out predictions from all folds
are pooled before computing that repetition's performance metrics.
Repeating this with fresh fold assignments (`repetitions` times)
characterizes how sensitive performance is to the particular fold split,
which matters most when the number of items is small relative to
`folds`.

Each fold's fit is checked for signs of instability — non-convergence,
non-finite or very large coefficients, or a "fitted probabilities
numerically 0 or 1 occurred" warning (a symptom of (quasi-)complete
separation, which is common with small samples and can inflate apparent
performance). See `diagnostics$unstable_fit`.

## Examples

``` r
# Two well-separated clusters in a 2D embedding
set.seed(1)
n <- 40
X <- rbind(
  cbind(rnorm(n / 2, mean = -2), rnorm(n / 2)),
  cbind(rnorm(n / 2, mean =  2), rnorm(n / 2))
)
y <- rep(c(0, 1), each = n / 2)

cv_result <- repeated_stratified_logistic_cv(
  X = X, y = y,
  repetitions = 5, folds = 3, seed = 1
)

# Mean performance and variability across repetitions
cv_result$summary
#>                              metric      mean         sd    median lower_2.5
#> accuracy                   accuracy 0.9850000 0.01369306 0.9750000 0.9750000
#> balanced_accuracy balanced_accuracy 0.9850000 0.01369306 0.9750000 0.9750000
#> sensitivity             sensitivity 1.0000000 0.00000000 1.0000000 1.0000000
#> specificity             specificity 0.9700000 0.02738613 0.9500000 0.9500000
#> precision                 precision 0.9714286 0.02608203 0.9523810 0.9523810
#> f1                               f1 0.9853659 0.01335909 0.9756098 0.9756098
#> auc                             auc 1.0000000 0.00000000 1.0000000 1.0000000
#>                   upper_97.5
#> accuracy                   1
#> balanced_accuracy          1
#> sensitivity                1
#> specificity                1
#> precision                  1
#> f1                         1
#> auc                        1

# Number of folds flagged as unstable
sum(cv_result$diagnostics$unstable_fit)
#> [1] 15
```
