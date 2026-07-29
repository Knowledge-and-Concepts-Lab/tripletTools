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
  random_state = NULL,
  geometry = c("euclidean", "sphere"),
  radius = 1,
  warm_start = NULL,
  norm_penalty = 0
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

- geometry:

  Either `"euclidean"` (default) or `"sphere"`. When `"sphere"`, items
  are placed on the surface of a `d`-dimensional sphere of radius
  `radius` (so `d = 2` embeds onto a circle) instead of freely in
  \\R^d\\. See the *Spherical embeddings* section below.

- radius:

  Radius of the sphere used when `geometry = "sphere"`. Ignored when
  `geometry = "euclidean"`. Default `1`.

- warm_start:

  Optional numeric matrix of shape \\n\_{\text{items}} \times d\\ giving
  existing embedding coordinates to start training from, instead of a
  random initialization. Row `i` (1-based) corresponds to the zero-based
  item index `i - 1` used in `X_train`/`X_test` — the same row order as
  the `embedding` this function returns, so a previous call's output can
  be passed straight back in.

  When `geometry = "sphere"`, pass an already-computed **Euclidean**
  embedding here (e.g. from a prior `geometry = "euclidean"` call on the
  same `X_train`/`X_test`/`d`) to skip the internal warm-start Euclidean
  fit described below and go straight to the constrained spherical fit —
  this avoids paying for that fit twice when you already have it. When
  `geometry = "euclidean"`, it is used directly as the starting point
  for training. `NULL` (default) starts from a random initialization
  (and, for `geometry = "sphere"`, still runs the internal Euclidean
  warm-start stage).

- norm_penalty:

  Non-negative number controlling how the "best" checkpoint is chosen
  during training (see *Early stopping* and *Diagnosing outlier items*
  below). Default `0` preserves prior behavior exactly: the checkpoint
  with the lowest raw `test_loss` is kept. A positive value instead
  keeps the checkpoint with the lowest
  `test_loss + norm_penalty * (norm_ratio - 1)`, so an epoch that only
  improved `test_loss` by growing an outlier item's norm is not
  necessarily preferred over an earlier, more compact epoch. The
  returned `loss` is always the raw `test_loss` of whichever checkpoint
  was selected, never the penalized value. Applied to every internal fit
  stage, including the Euclidean warm-start stage of
  `geometry = "sphere"`; has no effect on the constrained spherical
  stage itself, since `norm_ratio` is always `~1` there by construction.

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
  `test_loss`, `train_acc`, `test_acc`, `max_norm`, `median_norm`,
  `norm_ratio` — see *Diagnosing outlier items* below.

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
not necessarily the final-epoch embedding — unless `norm_penalty` is set
above `0`, in which case "best" is redefined as described under that
argument below, to avoid preferring an epoch that only improved loss by
growing an outlier item's norm.

## Item indices

Items are identified by zero-based integer indices. If your data uses
one-based indices (as is typical in R), subtract 1 from the `head`,
`winner`, and `loser` columns before passing them to this function.

## Progress output

Training progress is printed to the console every `print_every` epochs,
showing epoch number, train loss, test loss, train accuracy, and test
accuracy. A final line is printed when training stops, labelled
`[early stop]` if stopping was triggered before `max_epochs`.

## Spherical embeddings

Passing `geometry = "sphere"` constrains every item to the surface of a
`d`-dimensional sphere (`d = 2` is a circle) rather than letting it
range freely. This is useful when you have reason to believe the
underlying structure is inherently circular or spherical (e.g. hue,
phase, or other periodic variables) rather than merely embeddable in a
bounded Euclidean region.

Fitting a spherical embedding from a random start reliably gets stuck
near chance accuracy: constrained to the sphere's surface, each item has
only `d - 1` degrees of freedom to move along, which is too few for
gradient descent to escape a bad ordering. To avoid this,
`geometry = "sphere"` first fits a free Euclidean embedding (using the
same `max_epochs`/`tolerance`/`tol_window` schedule), projects it onto
the sphere, and uses that as the starting point for the constrained fit.
This roughly doubles training time relative to `geometry = "euclidean"`,
but is necessary for the constrained fit to find a good solution — see
the training output, which prints progress for both the warm-start stage
and the constrained stage. If you already have a Euclidean embedding of
the same items (e.g. from a previous `geometry = "euclidean"` call),
pass it as `warm_start` to skip this first stage entirely.

## Diagnosing outlier items

Hold-out loss can sometimes improve not because the fit is capturing
more shared structure, but because the optimizer has pushed one or two
weakly constrained items (e.g. ones involved in few triplets) far from
everything else — cheaply satisfying their few comparisons without
materially affecting the rest of the loss. `history` includes per-epoch
`max_norm`, `median_norm`, and `norm_ratio` (their ratio) to help catch
this: a `norm_ratio` that stays near `1` means items are roughly
equidistant from the origin, while a ratio that keeps growing across
epochs, dimensions, or restarts flags a drifting outlier worth
inspecting directly in `embedding`. This is only informative for
`geometry = "euclidean"` — under `geometry = "sphere"` every item's norm
is fixed at `radius` by construction, so `norm_ratio` is always `~1`
regardless of fit quality.

Once you've confirmed outlier drift is happening, `norm_penalty` lets
you push back on it directly rather than just observing it: it changes
which epoch's embedding training keeps as "best," discouraging (but not
forbidding) checkpoints that improved loss mainly by growing
`norm_ratio`. See the `norm_penalty` argument above.

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

# Embed onto a circle instead of freely in 2D
out_circle <- train_embedding(X_train, X_test, d = 2L,
                               geometry = "sphere", radius = 1)
plot(out_circle$embedding, asp = 1, xlab = "x", ylab = "y")

# Already have a Euclidean fit? Skip the internal warm-start stage.
out_euclid <- train_embedding(X_train, X_test, d = 2L)
out_circle2 <- train_embedding(X_train, X_test, d = 2L,
                                geometry = "sphere", radius = 1,
                                warm_start = out_euclid$embedding)

# Discourage checkpoints whose loss improvement came from an outlier
# item's norm growing rather than genuinely better structure
out_penalized <- train_embedding(X_train, X_test, d = 5L, norm_penalty = 0.05)
} # }
```
