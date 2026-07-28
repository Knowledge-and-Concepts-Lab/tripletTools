# Run the embedding pipeline from a triplet data list

A convenience wrapper around
[`run_embeddings`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings.md)
that accepts triplet data already loaded into R as a named list — the
format returned by
[`get.combined`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md)
— rather than reading from CSV files.

## Usage

``` r
run_embeddings_from_list(
  triplet_list,
  output_dir,
  d = 5L,
  max_epochs = 50000L,
  tolerance = 1e-04,
  tol_window = 10000L,
  seed = 222L,
  device = NULL,
  geometry = c("euclidean", "sphere"),
  radius = 1
)
```

## Arguments

- triplet_list:

  A named list of data frames, one per participant, as returned by
  [`get.combined`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md).
  Each data frame must contain the columns `worker_id`, `Center`,
  `Left`, `Right`, `Answer`, `sampleAlg`, and `sampleSet`.

- output_dir:

  Path to the directory where output CSV files will be saved. Created
  automatically if it does not already exist.

- d:

  Number of embedding dimensions. Default `5`.

- max_epochs:

  Maximum number of training epochs. Default `50000`.

- tolerance:

  Loss tolerance for early stopping. Default `1e-4`.

- tol_window:

  Epochs without improvement before early stopping triggers. Default
  `10000`.

- seed:

  Integer random seed for reproducibility. Default `222`.

- device:

  PyTorch device string, or `NULL` (default) to auto-select: CUDA GPU if
  available, then Apple MPS, then CPU. Pass `"cpu"` to force CPU even on
  a GPU machine.

- geometry:

  Either `"euclidean"` (default) or `"sphere"`. When `"sphere"`, items
  are placed on the surface of a `d`-dimensional sphere of radius
  `radius` (`d = 2` is a circle) instead of freely in \\R^d\\. See the
  *Spherical embeddings* section of
  [`train_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)
  for details, including why this roughly doubles training time.

- radius:

  Radius of the sphere used when `geometry = "sphere"`. Ignored when
  `geometry = "euclidean"`. Default `1`.

## Value

A named list with three elements:

- `individual`:

  Named list of numeric matrices, one per participant. Each matrix has
  one row per item (with item names as row names) and `d` columns
  (`dim_0`, `dim_1`, …).

- `group`:

  Numeric matrix of the group-level embedding, with item names as row
  names and `d` columns.

- `history`:

  Data frame with one row per worker (plus `"group"`) containing
  training diagnostics: `worker_id`, `lowest_loss`, `epoch`,
  `counter_from_last_update`, `n_train_triplets`, `n_test_triplets`.

## Details

The function converts items to consistent zero-based integer indices
(sorted alphabetically), writes temporary CSV files, calls the Python
embedding pipeline, and returns results in the standard `tripletTools`
format.

## Item indexing

All unique item names appearing in the `Center`, `Left`, and `Right`
columns across all participants are collected and sorted alphabetically.
Each item's zero-based index in this sorted list is used as the integer
index for the Python model. The same ordering is applied to all
participants so that indices are consistent across workers.

## Filtering

Trials with `sampleAlg == "check"` are excluded before fitting the
embedding (these are attention-check trials that do not reflect genuine
similarity judgments). The `sampleSet` column (indicating `"train"` or
`"test"`) must be present and is passed through unchanged.

## Examples

``` r
if (FALSE) { # \dontrun{
results <- run_embeddings_from_list(
  triplet_list = icon_triplets,
  output_dir   = "embeddings_output",
  d            = 3L,
  max_epochs   = 50000L
)

# Group embedding
head(results$group)

# First participant's individual embedding
head(results$individual[[1]])

# Training diagnostics
results$history
} # }
```
