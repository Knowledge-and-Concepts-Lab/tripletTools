# Write a list of participant triplet data frames to a CSV file

Converts a named or unnamed list of per-participant triplet data frames
– the package's standard `Center`/`Left`/`Right`/ `Answer`/`worker_id`
shape, e.g.
[`icon_triplets`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/icon_triplets.md)
– into a single combined CSV file, one row per trial. Counterpart to
[`write_embedding_list`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/write_embedding_list.md),
for triplet data rather than fitted embeddings; the result round-trips
through
[`get.combined`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md)
(`eflag = FALSE`).

## Usage

``` r
write_triplet_list(triplet_list, file)
```

## Arguments

- triplet_list:

  A list of data frames, one per participant, each with its own
  `worker_id` column (the format
  [`find_frequent_triplets`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_frequent_triplets.md)
  and
  [`assign_validation_from_frequency`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/assign_validation_from_frequency.md)
  also expect).

- file:

  Path to the output CSV file. The parent directory must already exist.

## Value

The output file path, invisibly.

## Details

Participants' data frames are combined with
[`bind_rows`](https://dplyr.tidyverse.org/reference/bind_rows.html)
rather than [`rbind()`](https://rdrr.io/r/base/cbind.html), so they
don't need to share identical columns or column order – a real
possibility for legacy data assembled from several sources (e.g. after
splitting off a held-out subset of participants, or combining data read
in separate batches).

## Output format

The CSV has one row per trial, with every column present in any element
of `triplet_list` (participants whose own data frame is missing a column
some other participant has get `NA` in that column, via
[`bind_rows`](https://dplyr.tidyverse.org/reference/bind_rows.html) –
see Details). Unlike
[`write_embedding_list`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/write_embedding_list.md),
`worker_id` is read directly from each data frame's own `worker_id`
column, not from `names(triplet_list)` – the list itself need not be
named (most of this package's own triplet lists, e.g. those built by
[`read_raw_data`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/read_raw_data.md),
are not).

## See also

[`write_embedding_list`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/write_embedding_list.md)
for the embedding-list analogue;
[`get.combined`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md)
to read the result back in.

## Examples

``` r
out <- tempfile(fileext = ".csv")
write_triplet_list(icon_triplets, out)

# Read back and reconstruct the named list
triplet_list <- get.combined(out, eflag = FALSE)
names(triplet_list)
#> [1] "3n7ggxph" "b5wma4no" "d8mmm1qn" "jn7bbjc0" "pbby694o" "sc2xbd6w"
```
