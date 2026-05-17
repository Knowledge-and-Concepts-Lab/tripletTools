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
#' not necessarily the final-epoch embedding.
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
#'     \code{test_acc}.}
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
#' }
train_embedding <- function(X_train,
                            X_test,
                            d           = 5L,
                            max_epochs  = 50000L,
                            tolerance   = 1e-4,
                            tol_window  = 10000L,
                            print_every = 100L) {
  compute_py <- .get_compute_py()
  np <- reticulate::import("numpy")

  X_train_np <- np$array(X_train, dtype = np$int32)
  X_test_np  <- np$array(X_test,  dtype = np$int32)

  result <- compute_py$train_embedding_model(
    X_train     = X_train_np,
    X_test      = X_test_np,
    d           = as.integer(d),
    max_epochs  = as.integer(max_epochs),
    tolerance   = tolerance,
    tol_window  = as.integer(tol_window),
    print_every = as.integer(print_every)
  )

  list(
    embedding = result[[1]],
    loss      = result[[2]],
    epoch     = result[[3]],
    counter   = result[[4]],
    history   = as.data.frame(result[[5]])
  )
}
