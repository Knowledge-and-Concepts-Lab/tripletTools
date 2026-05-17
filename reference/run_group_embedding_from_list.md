# Compute a group-level embedding from a triplet data list

Trains a single embedding on the combined triplet judgments from all
participants. Individual per-participant embeddings are not computed.
Use this function when you only need a group summary of the similarity
structure, which is faster than
[`run_embeddings_from_list`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md).

## Usage

``` r
run_group_embedding_from_list(
  triplet_list,
  d = 5L,
  max_epochs = 50000L,
  tolerance = 1e-04,
  tol_window = 10000L,
  seed = 222L,
  device = NULL
)
```

## Arguments

- triplet_list:

  A named list of data frames, one per participant, as returned by
  [`get.combined`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md).
  Each data frame must contain the columns `Center`, `Left`, `Right`,
  `Answer`, `sampleAlg`, and `sampleSet`.

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

## Value

A named list with three elements:

- `embedding`:

  Numeric matrix with one row per item (item names as row names) and `d`
  columns (`dim_0`, `dim_1`, …).

- `loss`:

  Best test loss achieved during training.

- `history`:

  Data frame with one row per epoch and columns `epoch`, `train_loss`,
  `test_loss`, `train_acc`, `test_acc`.

## Item indexing

All unique item names appearing in the `Center`, `Left`, and `Right`
columns across all participants are collected and sorted alphabetically.
Each item's zero-based index in this sorted list is used as the integer
index for the Python model.

## Filtering

Trials with `sampleAlg == "check"` are excluded. The `sampleSet` column
(`"train"` / `"test"`) must be present and is used to split data for
early stopping.

## Examples

``` r
if (FALSE) { # \dontrun{
grp <- run_group_embedding_from_list(
  triplet_list = icon_triplets,
  d            = 3L,
  max_epochs   = 50000L
)

# Embedding matrix (items x dimensions)
head(grp$embedding)

# Best test loss
grp$loss
} # }
```
