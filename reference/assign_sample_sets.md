# Assign trials to train or test sets

Randomly assigns each non-catch trial to either a training set or a test
set using a stratified split within each participant. Catch trials
(`sampleAlg == "check"`) receive `NA` and are excluded from both sets.

## Usage

``` r
assign_sample_sets(df, test_prop = 0.2, seed = 42)
```

## Arguments

- df:

  Data frame with columns `worker_id` and `sampleAlg`. `sampleAlg` must
  contain the values `"check"`, `"random"`, and/or `"validation"`.

- test_prop:

  Numeric between 0 and 1. Proportion of non-check trials to assign to
  the test set. Default: `0.2`.

- seed:

  Integer. Random seed passed to
  [`set.seed`](https://rdrr.io/r/base/Random.html) for reproducibility.
  Default: `42`.

## Value

The input data frame with an additional character column `sampleSet`
containing `"train"`, `"test"`, or `NA` (for catch trials).

## Details

The split is performed per participant so that each participant
contributes approximately `test_prop` of their trials to the test set.
Setting `seed` ensures the assignment is reproducible.

## Examples

``` r
if (FALSE) { # \dontrun{
d <- data.frame(
  worker_id = rep("p1", 10),
  sampleAlg = c(rep("random", 8), rep("check", 2))
)
assign_sample_sets(d, test_prop = 0.2, seed = 1)
} # }
```
