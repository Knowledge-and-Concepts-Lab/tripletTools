#' Fit one embedding restart and summarize it as a single result row
#'
#' Thin wrapper around \code{\link{train_embedding}} that extracts the
#' scalar summary values \code{\link{estimate_dimensionality}} and
#' \code{\link{estimate_learning_curve}} each record per (dimension,
#' restart) or (fraction, restart) job. Exported so external tooling (e.g.
#' a Condor per-job script running one restart at a time on a cluster) can
#' reproduce exactly the same per-restart fitting logic as those two
#' functions, rather than re-deriving it.
#'
#' @param X_train,X_test See \code{\link{train_embedding}}.
#' @param d,max_epochs,tolerance,tol_window,device,geometry,radius,norm_penalty
#'   Forwarded to \code{\link{train_embedding}}.
#' @param random_state Forwarded to \code{\link{train_embedding}}'s
#'   \code{random_state} argument, coerced to integer.
#'
#' @return A one-row data frame with columns:
#' \describe{
#'   \item{\code{loss}}{Best test loss achieved during training (identical
#'     to \code{train_embedding()}'s own \code{loss} return value).}
#'   \item{\code{accuracy}}{Test accuracy at the epoch of best test loss.}
#'   \item{\code{epoch_stopped}}{Epoch number at which training stopped
#'     (\code{train_embedding()}'s \code{epoch} return value) -- the epoch
#'     convention \code{\link{estimate_dimensionality}} records.}
#'   \item{\code{epoch_best}}{Epoch number of the best test loss -- the
#'     epoch convention \code{\link{estimate_learning_curve}} records.}
#'   \item{\code{norm_ratio}}{Ratio of the largest to median per-item
#'     embedding norm at the epoch of best test loss -- see the
#'     \emph{Diagnosing outlier items} section of
#'     \code{\link{train_embedding}}.}
#' }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' mats <- prepare_triplet_matrices(icon_triplets, seed = 1L)
#' fit_embedding_restart(
#'   X_train = mats$X_train, X_test = mats$X_test, d = 3L,
#'   random_state = 1L, max_epochs = 20000L, tolerance = 1e-4,
#'   tol_window = 10000L, device = NULL, geometry = "euclidean",
#'   radius = 1, norm_penalty = 0
#' )
#' }
fit_embedding_restart <- function(X_train, X_test, d, random_state,
                                   max_epochs, tolerance, tol_window, device,
                                   geometry, radius, norm_penalty) {
  out <- train_embedding(
    X_train      = X_train,
    X_test       = X_test,
    d            = d,
    max_epochs   = max_epochs,
    tolerance    = tolerance,
    tol_window   = tol_window,
    device       = device,
    random_state = as.integer(random_state),
    print_every  = as.integer(max_epochs),
    geometry     = geometry,
    radius       = radius,
    norm_penalty = norm_penalty
  )
  best <- out$history[which.min(out$history$test_loss), ]

  data.frame(
    loss          = out$loss,
    accuracy      = best$test_acc,
    epoch_stopped = out$epoch,
    epoch_best    = best$epoch,
    norm_ratio    = best$norm_ratio,
    stringsAsFactors = FALSE
  )
}
