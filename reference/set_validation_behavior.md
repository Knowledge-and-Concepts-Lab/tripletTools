# Set how validation trials are used in an already-split triplet dataset

Changes `sampleSet` for `sampleAlg == "validation"` trials only, leaving
every other trial's train/test assignment untouched. Useful when you've
already read data in (e.g. via
[`read_raw_data`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/read_raw_data.md)
or
[`get.combined`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md))
and want to switch whether validation trials are used to train an
embedding, held out as part of the ordinary test set, or excluded
entirely as a clean final evaluation set – without redoing the whole
train/test split.

## Usage

``` r
set_validation_behavior(triplets, mode = c("train", "test", "holdout"))
```

## Arguments

- triplets:

  A single triplet data frame, or a (optionally named) list of them –
  e.g. one element per participant, as returned by
  [`get.combined`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md).
  Each data frame must already have `sampleAlg` and `sampleSet` columns
  (i.e. it has already been through
  [`assign_sample_sets`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/assign_sample_sets.md)
  or equivalent).

- mode:

  One of `"train"`, `"test"`, or `"holdout"`: the `sampleSet` value to
  assign to validation trials. `"holdout"` sets it to `NA` instead of a
  string – the same treatment as check trials – excluding validation
  trials from training *and* from the test-loss-based model-selection
  criterion, so they stay a clean final evaluation set with no
  double-dipping. Evaluate on them afterward via
  [`get.hoacc`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md)'s
  `trialtype = "validation"`, which identifies them through `sampleAlg`
  rather than `sampleSet` for exactly this reason.

## Value

`triplets` with `sampleSet` updated for validation trials – a single
data frame if `triplets` was one, or a list (with names preserved) if it
was a list. Non-validation trials, and the `sampleAlg` column itself,
are returned unchanged.

## Examples

``` r
if (FALSE) { # \dontrun{
# Single participant
d <- set_validation_behavior(icon_triplets[[1]], mode = "test")

# A whole list of participants at once
triplets_test    <- set_validation_behavior(icon_triplets, mode = "test")
triplets_train   <- set_validation_behavior(icon_triplets, mode = "train")
triplets_holdout <- set_validation_behavior(icon_triplets, mode = "holdout")
} # }
```
