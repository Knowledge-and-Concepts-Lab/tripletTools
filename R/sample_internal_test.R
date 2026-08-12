#' Split a triplet matrix into a fitting subset and an internal-test subset
#'
#' Randomly partitions the rows of \code{X_train} into two disjoint subsets:
#' one to actually fit an embedding on, and a smaller held-out
#' \code{internal_test} subset to evaluate it against during training (early
#' stopping, and the per-restart loss/accuracy that
#' \code{\link{estimate_dimensionality}}/\code{\link{estimate_learning_curve}}
#' use for model selection).
#'
#' @section Why "internal_test" and not "validation":
#' This is deliberately not called a validation set, because
#' \code{sampleAlg == "validation"} already names a different, unrelated
#' concept in this package's data model: a fixed, pre-specified probe set of
#' triplets used to measure inter-subject agreement (see
#' \code{\link{icon_triplets}}, \code{\link{make_vmat}}). "internal_test" is
#' this function's own randomly-resampled, per-restart hold-out, drawn from
#' whatever \code{sampleSet == "train"} pool
#' \code{\link{prepare_triplet_matrices}} already isolated -- it is
#' unrelated to, and does not touch, either of those.
#'
#' @param X_train Integer matrix of shape \eqn{n \times 3} with columns
#'   \code{head}, \code{winner}, \code{loser} -- typically the \code{X_train}
#'   element returned by \code{\link{prepare_triplet_matrices}}.
#' @param frac Proportion of \code{X_train}'s rows to hold out as
#'   \code{X_internal_test}. Must satisfy \code{0 < frac < 1}.
#' @param seed Integer seed controlling the random partition. Passing the
#'   same seed always returns the same split.
#'
#' @return A named list with two elements:
#' \describe{
#'   \item{\code{X_fit}}{Integer matrix with the same three columns as
#'     \code{X_train}, containing the rows to actually fit on.}
#'   \item{\code{X_internal_test}}{Integer matrix with the same three
#'     columns, containing \code{floor(frac * nrow(X_train))} rows.}
#' }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' mats  <- prepare_triplet_matrices(icon_triplets, seed = 1L)
#' split <- sample_internal_test(mats$X_train, frac = 0.1, seed = 42L)
#' nrow(split$X_fit)
#' nrow(split$X_internal_test)
#' }
sample_internal_test <- function(X_train, frac, seed) {
  if (!is.numeric(frac) || length(frac) != 1L || is.na(frac) || frac <= 0 || frac >= 1) {
    stop("frac must be a single number strictly between 0 and 1", call. = FALSE)
  }

  n <- nrow(X_train)
  n_internal_test <- floor(frac * n)
  if (n_internal_test < 1L || n_internal_test >= n) {
    stop(sprintf(
      "X_train has too few rows (%d) to split at frac = %s: this would give %d internal_test row(s) and %d fit row(s), and both must be non-empty",
      n, format(frac), n_internal_test, n - n_internal_test
    ), call. = FALSE)
  }

  set.seed(seed)
  shuffled <- X_train[sample(n), , drop = FALSE]
  n_fit    <- n - n_internal_test

  list(
    X_fit           = shuffled[seq_len(n_fit), , drop = FALSE],
    X_internal_test = shuffled[seq(n_fit + 1L, n), , drop = FALSE]
  )
}
