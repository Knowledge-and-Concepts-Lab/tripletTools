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
  device = NULL,
  geometry = c("euclidean", "sphere"),
  radius = 1,
  warm_start = NULL
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

- warm_start:

  Optional numeric matrix of existing embedding coordinates to start
  training from, instead of a random initialization — for example, the
  `embedding` returned by a previous call to this function. Must have
  row names matching item names and `d` columns; rows are matched and
  reordered by name, so `warm_start` does not need to list items in the
  same order as this call (every item present in `triplet_list` must
  have a matching row name, though).

  When `geometry = "sphere"`, pass an already-computed **Euclidean**
  embedding of the same items (e.g. from a prior
  `geometry = "euclidean"` call) to skip the internal warm-start
  Euclidean fit — see the *Spherical embeddings* section of
  [`train_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)
  for why that stage normally runs. When `geometry = "euclidean"`, it is
  used directly as the starting point for training. `NULL` (default)
  starts from a random initialization.

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

# Already have a Euclidean fit of the same items? Skip the internal
# warm-start stage when fitting a spherical embedding.
grp_circle <- run_group_embedding_from_list(
  triplet_list = icon_triplets,
  d            = 2L,
  geometry     = "sphere",
  warm_start   = grp$embedding
)
} # }
```
