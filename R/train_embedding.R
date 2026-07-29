#' Train a single triplet embedding model
#'
#' A lower-level interface to the embedding pipeline.  Use this function when
#' you want to manage the train/test split in R rather than relying on the
#' \code{sampleSet} column in your data, or when you want to train an
#' embedding on a single subset of responses.
#'
#' For processing all workers in a dataset at once, see
#' \code{\link{run_embeddings}} and \code{\link{run_embeddings_from_list}}.
#'
#' @section Early stopping:
#' Training runs for up to \code{max_epochs} passes through the training data.
#' It stops early if the test loss is within \code{tolerance} of the best
#' observed test loss for more than \code{tol_window} consecutive epochs.
#' The embedding that achieved the best test loss during training is returned,
#' not necessarily the final-epoch embedding — unless \code{norm_penalty} is
#' set above \code{0}, in which case "best" is redefined as described under
#' that argument below, to avoid preferring an epoch that only improved loss
#' by growing an outlier item's norm.
#'
#' @section Item indices:
#' Items are identified by zero-based integer indices.  If your data uses
#' one-based indices (as is typical in R), subtract 1 from the
#' \code{head}, \code{winner}, and \code{loser} columns before passing them
#' to this function.
#'
#' @section Progress output:
#' Training progress is printed to the console every \code{print_every}
#' epochs, showing epoch number, train loss, test loss, train accuracy, and
#' test accuracy.  A final line is printed when training stops, labelled
#' \code{[early stop]} if stopping was triggered before \code{max_epochs}.
#'
#' @param X_train Integer matrix of shape \eqn{n_{\text{triplets}} \times 3}.
#'   Columns must be \code{head}, \code{winner}, \code{loser} in that order,
#'   with zero-based integer item indices.  Pass using
#'   \code{as.matrix(df[, c("head", "winner", "loser")])}.
#' @param X_test Integer matrix in the same format as \code{X_train}, used
#'   for computing validation metrics and triggering early stopping.
#' @param d Number of embedding dimensions.  Default \code{5}.
#' @param max_epochs Maximum number of training epochs.  Default \code{50000}.
#' @param tolerance  Loss tolerance for early stopping.  Default \code{1e-4}.
#' @param tol_window Number of epochs the loss must remain within
#'   \code{tolerance} of the best before training halts early.
#'   Default \code{10000}.
#' @param print_every Print a progress line every this many epochs.
#'   Default \code{100}.  Increase to reduce console output; set to
#'   \code{max_epochs} to suppress mid-training output entirely.
#' @param device PyTorch device string, or \code{NULL} (default) to
#'   auto-select: CUDA GPU if available, then Apple MPS, then CPU.
#'   Pass \code{"cpu"} to force CPU even on a GPU machine.
#' @param random_state Integer seed passed to both NumPy and PyTorch before
#'   training begins.  \code{NULL} (default) leaves the global random state
#'   unchanged.  Set this when you need reproducible embeddings, e.g. when
#'   comparing multiple random restarts.
#' @param geometry Either \code{"euclidean"} (default) or \code{"sphere"}.
#'   When \code{"sphere"}, items are placed on the surface of a
#'   \code{d}-dimensional sphere of radius \code{radius} (so \code{d = 2}
#'   embeds onto a circle) instead of freely in \eqn{R^d}.  See the
#'   \emph{Spherical embeddings} section below.
#' @param radius Radius of the sphere used when \code{geometry = "sphere"}.
#'   Ignored when \code{geometry = "euclidean"}.  Default \code{1}.
#' @param warm_start Optional numeric matrix of shape
#'   \eqn{n_{\text{items}} \times d} giving existing embedding coordinates to
#'   start training from, instead of a random initialization.  Row \code{i}
#'   (1-based) corresponds to the zero-based item index \code{i - 1} used in
#'   \code{X_train}/\code{X_test} — the same row order as the \code{embedding}
#'   this function returns, so a previous call's output can be passed
#'   straight back in.
#'
#'   When \code{geometry = "sphere"}, pass an already-computed \strong{Euclidean}
#'   embedding here (e.g. from a prior \code{geometry = "euclidean"} call on
#'   the same \code{X_train}/\code{X_test}/\code{d}) to skip the internal
#'   warm-start Euclidean fit described below and go straight to the
#'   constrained spherical fit — this avoids paying for that fit twice when
#'   you already have it.  When \code{geometry = "euclidean"}, it is used
#'   directly as the starting point for training.  \code{NULL} (default)
#'   starts from a random initialization (and, for \code{geometry = "sphere"},
#'   still runs the internal Euclidean warm-start stage).
#' @param norm_penalty Non-negative number controlling how the "best"
#'   checkpoint is chosen during training (see \emph{Early stopping} and
#'   \emph{Diagnosing outlier items} below).  Default \code{0} preserves
#'   prior behavior exactly: the checkpoint with the lowest raw
#'   \code{test_loss} is kept.  A positive value instead keeps the
#'   checkpoint with the lowest \code{test_loss + norm_penalty * (norm_ratio - 1)},
#'   so an epoch that only improved \code{test_loss} by growing an outlier
#'   item's norm is not necessarily preferred over an earlier, more compact
#'   epoch.  The returned \code{loss} is always the raw \code{test_loss} of
#'   whichever checkpoint was selected, never the penalized value.  Applied
#'   to every internal fit stage, including the Euclidean warm-start stage
#'   of \code{geometry = "sphere"}; has no effect on the constrained
#'   spherical stage itself, since \code{norm_ratio} is always \code{~1}
#'   there by construction.
#'
#' @section Spherical embeddings:
#' Passing \code{geometry = "sphere"} constrains every item to the surface of
#' a \code{d}-dimensional sphere (\code{d = 2} is a circle) rather than
#' letting it range freely.  This is useful when you have reason to believe
#' the underlying structure is inherently circular or spherical (e.g. hue,
#' phase, or other periodic variables) rather than merely embeddable in a
#' bounded Euclidean region.
#'
#' Fitting a spherical embedding from a random start reliably gets stuck near
#' chance accuracy: constrained to the sphere's surface, each item has only
#' \code{d - 1} degrees of freedom to move along, which is too few for
#' gradient descent to escape a bad ordering.  To avoid this,
#' \code{geometry = "sphere"} first fits a free Euclidean embedding (using the
#' same \code{max_epochs}/\code{tolerance}/\code{tol_window} schedule),
#' projects it onto the sphere, and uses that as the starting point for the
#' constrained fit.  This roughly doubles training time relative to
#' \code{geometry = "euclidean"}, but is necessary for the constrained fit to
#' find a good solution — see the training output, which prints progress for
#' both the warm-start stage and the constrained stage.  If you already have
#' a Euclidean embedding of the same items (e.g. from a previous
#' \code{geometry = "euclidean"} call), pass it as \code{warm_start} to skip
#' this first stage entirely.
#'
#' @section Diagnosing outlier items:
#' Hold-out loss can sometimes improve not because the fit is capturing more
#' shared structure, but because the optimizer has pushed one or two weakly
#' constrained items (e.g. ones involved in few triplets) far from everything
#' else — cheaply satisfying their few comparisons without materially
#' affecting the rest of the loss.  \code{history} includes per-epoch
#' \code{max_norm}, \code{median_norm}, and \code{norm_ratio} (their ratio)
#' to help catch this: a \code{norm_ratio} that stays near \code{1} means
#' items are roughly equidistant from the origin, while a ratio that keeps
#' growing across epochs, dimensions, or restarts flags a drifting outlier
#' worth inspecting directly in \code{embedding}.  This is only informative
#' for \code{geometry = "euclidean"} — under \code{geometry = "sphere"} every
#' item's norm is fixed at \code{radius} by construction, so
#' \code{norm_ratio} is always \code{~1} regardless of fit quality.
#'
#' Once you've confirmed outlier drift is happening, \code{norm_penalty} lets
#' you push back on it directly rather than just observing it: it changes
#' which epoch's embedding training keeps as "best," discouraging (but not
#' forbidding) checkpoints that improved loss mainly by growing
#' \code{norm_ratio}.  See the \code{norm_penalty} argument above.
#'
#' @return A named list with five elements:
#' \describe{
#'   \item{\code{embedding}}{Numeric matrix of shape
#'     \eqn{n_{\text{items}} \times d} containing the learned positions.
#'     Rows correspond to items in index order.}
#'   \item{\code{loss}}{Best test loss achieved during training.}
#'   \item{\code{epoch}}{Epoch number at which training stopped.}
#'   \item{\code{counter}}{Number of epochs since the last meaningful
#'     improvement at the point training stopped.}
#'   \item{\code{history}}{Data frame with one row per epoch and columns
#'     \code{epoch}, \code{train_loss}, \code{test_loss}, \code{train_acc},
#'     \code{test_acc}, \code{max_norm}, \code{median_norm},
#'     \code{norm_ratio} — see \emph{Diagnosing outlier items} below.}
#' }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' triplets <- read.csv("triplets.csv")
#'
#' is_train <- triplets$sampleSet == "train"
#' X_train  <- as.matrix(triplets[is_train,  c("head", "winner", "loser")])
#' X_test   <- as.matrix(triplets[!is_train, c("head", "winner", "loser")])
#'
#' out <- train_embedding(X_train, X_test, d = 5L, max_epochs = 50000L)
#'
#' dim(out$embedding)           # n_items x 5
#' cat("Best loss:", out$loss, "\n")
#' cat("Stopped at epoch:", out$epoch, "\n")
#'
#' # Per-epoch training curve
#' head(out$history)
#' plot(out$history$epoch, out$history$test_loss, type = "l",
#'      xlab = "Epoch", ylab = "Test loss")
#'
#' # Embed onto a circle instead of freely in 2D
#' out_circle <- train_embedding(X_train, X_test, d = 2L,
#'                                geometry = "sphere", radius = 1)
#' plot(out_circle$embedding, asp = 1, xlab = "x", ylab = "y")
#'
#' # Already have a Euclidean fit? Skip the internal warm-start stage.
#' out_euclid <- train_embedding(X_train, X_test, d = 2L)
#' out_circle2 <- train_embedding(X_train, X_test, d = 2L,
#'                                 geometry = "sphere", radius = 1,
#'                                 warm_start = out_euclid$embedding)
#'
#' # Discourage checkpoints whose loss improvement came from an outlier
#' # item's norm growing rather than genuinely better structure
#' out_penalized <- train_embedding(X_train, X_test, d = 5L, norm_penalty = 0.05)
#' }
train_embedding <- function(X_train,
                            X_test,
                            d            = 5L,
                            max_epochs   = 50000L,
                            tolerance    = 1e-4,
                            tol_window   = 10000L,
                            print_every  = 100L,
                            device       = NULL,
                            random_state = NULL,
                            geometry     = c("euclidean", "sphere"),
                            radius       = 1,
                            warm_start   = NULL,
                            norm_penalty = 0) {
  geometry <- match.arg(geometry)

  compute_py <- .get_compute_py()
  np <- reticulate::import("numpy")

  X_train_np <- np$array(X_train, dtype = np$int32)
  X_test_np  <- np$array(X_test,  dtype = np$int32)

  warm_start_np <- NULL
  if (!is.null(warm_start)) {
    warm_start <- as.matrix(warm_start)
    n_items <- max(X_train, X_test) + 1L
    if (nrow(warm_start) != n_items || ncol(warm_start) != d) {
      stop(sprintf(
        "warm_start must have shape (%d, %d) to match X_train/X_test and d, got (%d, %d)",
        n_items, d, nrow(warm_start), ncol(warm_start)
      ))
    }
    warm_start_np <- np$array(warm_start, dtype = np$float32)
  }

  result <- compute_py$train_embedding_model(
    X_train      = X_train_np,
    X_test       = X_test_np,
    d            = as.integer(d),
    max_epochs   = as.integer(max_epochs),
    tolerance    = tolerance,
    tol_window   = as.integer(tol_window),
    print_every  = as.integer(print_every),
    device       = device,
    random_state = if (is.null(random_state)) NULL else as.integer(random_state),
    geometry     = geometry,
    radius       = radius,
    warm_start   = warm_start_np,
    norm_penalty = norm_penalty
  )

  list(
    embedding = result[[1]],
    loss      = result[[2]],
    epoch     = result[[3]],
    counter   = result[[4]],
    history   = as.data.frame(result[[5]])
  )
}
