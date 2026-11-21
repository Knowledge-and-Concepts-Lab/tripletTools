# Fold the alpha-profiling sub-pool back into training

Once \\\alpha\\ has been estimated by
[`estimate_group_alpha`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_group_alpha.md),
the sub-pool of `sampleSet == "test"` trials it reserved for profiling
\\\alpha\\ (`alpha_test_rows`, part of its return value) has no further
job to do – \\\alpha\\ is now a fixed number, not something being
estimated from anything. Holding that sub-pool out of training any
longer is pure waste: there is nothing left for it to stay independent
*from*. This function sets `sampleSet <- "train"` at exactly those rows
(and no others – in particular, the remaining `test_fit` sub-pool is
left as `"test"`, since it still has a job: governing early stopping for
the one last fit at the now-fixed \\\alpha\\).

## Usage

``` r
fold_alpha_test_to_train(triplet_list, alpha_test_rows)
```

## Arguments

- triplet_list:

  A named or unnamed list of per-participant data frames, each with a
  `sampleSet` column – the same object passed to
  [`estimate_group_alpha`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_group_alpha.md).

- alpha_test_rows:

  Integer vector, typically `estimate_group_alpha(...)$alpha_test_rows`
  from a call on this same `triplet_list`: positions (1-based) into
  `do.call(rbind, triplet_list)` to flip from `"test"` to `"train"`.

## Value

`triplet_list` with `sampleSet` updated at `alpha_test_rows`; a list of
the same length, names, and row order as the input. No other column, and
no other row's `sampleSet`, is touched.

## Why this is a mechanical flip, not a re-derivation

`alpha_test_rows` must come from a call to
[`estimate_group_alpha`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_group_alpha.md)
on this exact same `triplet_list` (same participants, same row order
within each). This function does not re-run any random split itself – it
just flips `sampleSet` at the positions it's given – so there is no risk
of drifting out of sync with what \\\alpha\\ was actually profiled on,
the way independently re-deriving an equivalent split (e.g. replaying
[`sample_internal_test`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/sample_internal_test.md)
a second time with the same seed) would risk if any upstream detail ever
changed.

## Examples

``` r
if (FALSE) { # \dontrun{
grp <- run_group_embedding_from_list(icon_triplets, d = 3L)
joint <- estimate_group_alpha(icon_triplets, warm_start = grp$embedding)
folded <- fold_alpha_test_to_train(icon_triplets, joint$alpha_test_rows)
# Now fit the real final embedding at (d, joint$alpha) on `folded`,
# e.g. with several random-seed restarts, keeping the lowest test loss.
} # }
```
