# Build train/test triplet matrices from a list of participant data frames

Collects and sorts all unique item names across participants, converts
each participant's `Center`/`Left`/`Right`/`Answer` columns to
zero-based `head`/`winner`/`loser` integer indices, and splits into
`X_train`/`X_test` matrices.

## Usage

``` r
prepare_triplet_matrices(triplet_list, seed = 1L)
```

## Arguments

- triplet_list:

  A named list of data frames, one per participant, as returned by
  [`get.combined`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md).
  Each data frame must contain columns `Center`, `Left`, `Right`,
  `Answer`, and `sampleSet`.

- seed:

  Integer seed for the fallback random 70/30 split. Only used when
  `sampleSet` is absent or entirely `NA`. Default `1L`.

## Value

A named list with three elements:

- `X_train`:

  Integer matrix of shape \\n\_{\text{train}} \times 3\\ with columns
  `head`, `winner`, `loser`.

- `X_test`:

  Integer matrix in the same format as `X_train`.

- `all_items`:

  Character vector of item names, sorted alphabetically – row `i`
  (1-based) of this vector is the item at zero-based index `i - 1` in
  `X_train`/`X_test`.

## Item indexing

All unique item names in `Center`, `Left`, and `Right` across all
participants are collected and sorted alphabetically; this sorted order
defines the zero-based integer indices used in the returned matrices,
and is also returned as `all_items` so callers can restore item names on
a fitted embedding afterward.

## Filtering

Trials with `NA` in the `sampleSet` column (attention-check trials) are
excluded before splitting. The `sampleSet` column (`"train"` / `"test"`)
defines the split. If no `sampleSet` column is present, or all its
values are `NA`, a 70/30 random train/test split is used instead,
controlled by `seed`.

## Examples

``` r
if (FALSE) { # \dontrun{
mats <- prepare_triplet_matrices(icon_triplets, seed = 1L)
dim(mats$X_train)
head(mats$all_items)
} # }
```
