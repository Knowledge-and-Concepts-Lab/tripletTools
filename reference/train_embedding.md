# Train a single triplet embedding model

A lower-level interface to the embedding pipeline. Use this function
when you want to manage the train/test split in R rather than relying on
the `sampleSet` column in your data, or when you want to train an
embedding on a single subset of responses.

## Usage

``` r
train_embedding(
  X_train,
  X_test,
  d = 5L,
  max_epochs = 50000L,
  tolerance = 1e-04,
  tol_window = 10000L,
  print_every = 100L,
  device = NULL,
  random_state = NULL
)
```

## Arguments

- X_train:

  Integer matrix of shape \\n\_{\text{triplets}} \times 3\\. Columns
  must be `head`, `winner`, `loser` in that order, with zero-based
  integer item indices. Pass using
  `as.matrix(df[, c("head", "winner", "loser")])`.

- X_test:

  Integer matrix in the same format as `X_train`, used for computing
  validation metrics and triggering early stopping.

- d:

  Number of embedding dimensions. Default `5`.

- max_epochs:

  Maximum number of training epochs. Default `50000`.

- tolerance:

  Loss tolerance for early stopping. Default `1e-4`.

- tol_window:

  Number of epochs the loss must remain within `tolerance` of the best
  before training halts early. Default `10000`.

- print_every:

  Print a progress line every this many epochs. Default `100`. Increase
  to reduce console output; set to `max_epochs` to suppress mid-training
  output entirely.

- device:

  PyTorch device string, or `NULL` (default) to auto-select: CUDA GPU if
  available, then Apple MPS, then CPU. Pass `"cpu"` to force CPU even on
  a GPU machine.

- random_state:

  Integer seed passed to both NumPy and PyTorch before training begins.
  `NULL` (default) leaves the global random state unchanged. Set this
  when you need reproducible embeddings, e.g. when comparing multiple
  random restarts.

## Value

A named list with five elements:

- `embedding`:

  Numeric matrix of shape \\n\_{\text{items}} \times d\\ containing the
  learned positions. Rows correspond to items in index order.

- `loss`:

  Best test loss achieved during training.

- `epoch`:

  Epoch number at which training stopped.

- `counter`:

  Number of epochs since the last meaningful improvement at the point
  training stopped.

- `history`:

  Data frame with one row per epoch and columns `epoch`, `train_loss`,
  `test_loss`, `train_acc`, `test_acc`.

## Details

For processing all workers in a dataset at once, see
[`run_embeddings`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings.md)
and
[`run_embeddings_from_list`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md).

## Early stopping

Training runs for up to `max_epochs` passes through the training data.
It stops early if the test loss is within `tolerance` of the best
observed test loss for more than `tol_window` consecutive epochs. The
embedding that achieved the best test loss during training is returned,
not necessarily the final-epoch embedding.

## Item indices

Items are identified by zero-based integer indices. If your data uses
one-based indices (as is typical in R), subtract 1 from the `head`,
`winner`, and `loser` columns before passing them to this function.

## Progress output

Training progress is printed to the console every `print_every` epochs,
showing epoch number, train loss, test loss, train accuracy, and test
accuracy. A final line is printed when training stops, labelled
`[early stop]` if stopping was triggered before `max_epochs`.

## Examples

``` r
if (FALSE) { # \dontrun{
triplets <- read.csv("triplets.csv")

is_train <- triplets$sampleSet == "train"
X_train  <- as.matrix(triplets[is_train,  c("head", "winner", "loser")])
X_test   <- as.matrix(triplets[!is_train, c("head", "winner", "loser")])

out <- train_embedding(X_train, X_test, d = 5L, max_epochs = 50000L)

dim(out$embedding)           # n_items x 5
cat("Best loss:", out$loss, "\n")
cat("Stopped at epoch:", out$epoch, "\n")

# Per-epoch training curve
head(out$history)
plot(out$history$epoch, out$history$test_loss, type = "l",
     xlab = "Epoch", ylab = "Test loss")
} # }
```
