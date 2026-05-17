# Run the full embedding pipeline for all workers

Reads triplet comparison data from `input_file`, trains a separate
embedding model with early stopping for each worker, and then trains a
combined group-level embedding across all workers. Output CSV files are
written to `output_dir` and the results are also returned as R data
frames.

## Usage

``` r
run_embeddings(
  input_file,
  additional_data_file,
  output_dir,
  d = 5L,
  max_epochs = 50000L,
  tolerance = 1e-04,
  tol_window = 10000L,
  seed = 222L,
  device = NULL
)
```

## Arguments

- input_file:

  Path to the CSV file containing all triplets (see *Input format*
  above).

- additional_data_file:

  Path to a CSV file with item metadata to append to the embedding
  output (e.g. image filenames listed in alphabetical order). The number
  of rows should match the number of unique items.

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

## Value

A named list with two elements:

- `history`:

  Data frame with one row per worker (plus one for the group model)
  containing: `worker_id`, `lowest_loss`, `epoch`,
  `counter_from_last_update`, `n_train_triplets`, `n_test_triplets`.

- `embeddings`:

  Data frame of all embeddings concatenated, with dimension columns
  (`dim_0`, `dim_1`, …), a `worker_id` column, and any columns from
  `additional_data_file`.

## Details

For a higher-level interface that accepts triplet data already loaded
into R as a named list (the format returned by
[`get.combined`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md)),
see
[`run_embeddings_from_list`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md).

## Input format

`input_file` must be a CSV with at least the following columns:

- `worker_id`:

  Identifier for the respondent.

- `head`:

  Zero-based integer index of the reference item.

- `winner`:

  Zero-based integer index of the item judged closer to `head`.

- `loser`:

  Zero-based integer index of the item judged further from `head`.

- `sampleSet`:

  Either `"train"` or `"test"`, used to split data for early stopping.

## Output files

Three CSV files are written to `output_dir`:

- `model_history.csv`:

  Training history: loss, stopping epoch, and triplet counts for each
  worker.

- `embeddings_group.csv`:

  Group-level embedding only.

- `embeddings.csv`:

  All per-worker and group-level embeddings concatenated.

## Examples

``` r
if (FALSE) { # \dontrun{
results <- run_embeddings(
  input_file           = "triplets.csv",
  additional_data_file = "item_labels.csv",
  output_dir           = "embeddings_output",
  d                    = 5L,
  max_epochs           = 50000L
)

head(results$history)
head(results$embeddings)
} # }
```
