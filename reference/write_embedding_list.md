# Write a list of individual embeddings to a CSV file

Converts a named list of embedding matrices — as returned by the
`$individual` element of
[`run_embeddings_from_list`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md)
— into a flat CSV file with one row per item per participant.

## Usage

``` r
write_embedding_list(embedding_list, file)
```

## Arguments

- embedding_list:

  A named list of numeric matrices, one per participant. Each matrix
  must have item names as row names and embedding dimension columns
  named `dim_0`, `dim_1`, etc. This is the format of the `$individual`
  element returned by
  [`run_embeddings_from_list`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md).

- file:

  Path to the output CSV file. The parent directory must already exist.

## Value

The output file path, invisibly.

## Output format

The CSV has one row per (participant, item) combination and the
following columns:

- `worker_id`:

  Participant identifier, taken from the names of `embedding_list`.

- `item`:

  Item name, taken from the row names of each matrix.

- `dim_0`, `dim_1`, …:

  Embedding coordinates. Column names are taken directly from the column
  names of each matrix.

## Examples

``` r
if (FALSE) { # \dontrun{
results <- run_embeddings_from_list(
  triplet_list = icon_triplets,
  output_dir   = "embeddings_output",
  d            = 3L
)

# Write individual embeddings to a single flat CSV
write_embedding_list(results$individual, "embeddings_individual.csv")

# Read back and reconstruct the named list
df       <- read.csv("embeddings_individual.csv")
dim_cols <- grep("^dim_", names(df), value = TRUE)
embedding_list <- lapply(
  split(df, df$worker_id),
  function(sub) {
    m <- as.matrix(sub[, dim_cols])
    row.names(m) <- sub$item
    m
  }
)
} # }
```
