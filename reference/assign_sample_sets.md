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
  validation_mode = c("train", "test", "holdout")
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

- validation_mode:

  One of `"train"` (the default), `"test"`, or `"holdout"` – where
  `sampleAlg == "validation"` trials are routed. See *Validation trials*
  below.

## Value

The input data frame with an additional character column `sampleSet`
containing `"train"`, `"test"`, or `NA` (for catch trials, and for
validation trials when `validation_mode = "holdout"`).

## Details

The split is performed per participant: within each participant's
`sampleAlg == "random"` trials, exactly `round(test_prop * n_random)` of
them (chosen uniformly at random, without replacement) are assigned to
the test set, and the rest to train. Using an exact count rather than an
independent per-trial coin-flip means two participants with the same
number of random trials always get the same number (and proportion) of
test trials – not just approximately, as an i.i.d. Bernoulli draw per
trial would give – and participants with different trial counts still
get matched *proportions*, with the exact per-participant count
controlled by rounding. Setting `seed` ensures the assignment is
reproducible.

## Validation trials

`sampleAlg == "validation"` trials are a separate category from the
`"random"` trials that `test_prop` splits – they're routed entirely by
`validation_mode` instead: all to `"train"` (the default) when they're
not being used to evaluate an embedding, all to `"test"` when they are,
or all to `NA` (excluded from both – same treatment as check trials)
when you want them held out as a clean final evaluation set that never
influences training *or* the early-stopping/model-selection criterion,
avoiding the double-dipping that comes from putting them in the ordinary
test set a model is also selected against. Use
[`get.hoacc`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md)'s
`trialtype = "validation"` to evaluate on them afterward (it identifies
them via `sampleAlg`, not `sampleSet`, since `sampleSet` no longer
labels them as anything once they're excluded this way). Re-running this
function on the same `df` (which must still have `sampleAlg`, so this
only works before it's dropped from a pipeline's output) with the same
`seed` but a different `validation_mode` reproduces an identical
`"random"`-trial split and only changes validation trials, since
validation rows never consume any of the random draws `test_prop` uses.
[`set_validation_behavior`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/set_validation_behavior.md)
offers the same three modes for data that's already been through this
function, without redoing the `"random"`-trial split.

## Examples

``` r
if (FALSE) { # \dontrun{
d <- data.frame(
  worker_id = rep("p1", 10),
  sampleAlg = c(rep("random", 6), rep("check", 2), rep("validation", 2))
)
assign_sample_sets(d, test_prop = 0.2, seed = 1)
# Hold validation trials out for evaluation instead:
assign_sample_sets(d, test_prop = 0.2, seed = 1, validation_mode = "test")
# Exclude them from training and model selection entirely, for use as a
# clean final evaluation set via get.hoacc(trialtype = "validation"):
assign_sample_sets(d, test_prop = 0.2, seed = 1, validation_mode = "holdout")
} # }
```
