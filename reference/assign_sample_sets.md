# Assign trials to train or test sets

Randomly assigns each non-catch trial to either a training set or a test
set using a stratified split within each participant. Catch trials
(`sampleAlg == "check"`) receive `NA` and are excluded from both sets.

## Usage

``` r
assign_sample_sets(
  df,
  test_prop = 0.2,
  seed = 42,
  train_with_validation = TRUE
)
```

## Arguments

- df:

  Data frame with columns `worker_id` and `sampleAlg`. `sampleAlg` must
  contain the values `"check"`, `"random"`, and/or `"validation"`.

- test_prop:

  Numeric between 0 and 1. Proportion of non-check, non-validation
  trials to assign to the test set. Default: `0.2`.

- seed:

  Integer. Random seed passed to
  [`set.seed`](https://rdrr.io/r/base/Random.html) for reproducibility.
  Default: `42`.

- train_with_validation:

  Logical. Whether `sampleAlg == "validation"` trials are assigned to
  `"train"` (`TRUE`, the default) or `"test"` (`FALSE`) – set this to
  `FALSE` when validation trials are instead being held out to evaluate
  a fitted embedding. See *Validation trials* below.

## Value

The input data frame with an additional character column `sampleSet`
containing `"train"`, `"test"`, or `NA` (for catch trials).

## Details

The split is performed per participant so that each participant
contributes approximately `test_prop` of their trials to the test set.
Setting `seed` ensures the assignment is reproducible.

## Validation trials

`sampleAlg == "validation"` trials are a separate category from the
`"random"` trials that `test_prop` splits – they're routed entirely by
`train_with_validation` instead: all to `"train"` (the default) when
they're not being used to evaluate an embedding, or all to `"test"` when
they are. Re-running this function on the same `df` (which must still
have `sampleAlg`, so this only works before it's dropped from a
pipeline's output) with the same `seed` but a different
`train_with_validation` reproduces an identical `"random"`-trial split
and only changes validation trials, since validation rows never consume
any of the random draws `test_prop` uses.

## Examples

``` r
if (FALSE) { # \dontrun{
d <- data.frame(
  worker_id = rep("p1", 10),
  sampleAlg = c(rep("random", 6), rep("check", 2), rep("validation", 2))
)
assign_sample_sets(d, test_prop = 0.2, seed = 1)
# Hold validation trials out for evaluation instead:
assign_sample_sets(d, test_prop = 0.2, seed = 1, train_with_validation = FALSE)
} # }
```
