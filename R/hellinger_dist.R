#' Pairwise Hellinger distances between rows of a profile matrix
#'
#' Given a matrix of non-negative profiles (e.g. category membership
#' probabilities, or any set of values that can be normalized to sum to 1
#' within a row), computes the Hellinger distance between every pair of
#' rows.
#'
#' @param P Numeric matrix (or object coercible to one) with non-negative
#'   entries, rows = items, columns = profile categories. Rows do not need
#'   to already sum to 1 — they are renormalized internally.
#'
#' @return An object of class \code{"dist"} (as returned by
#'   \code{\link[stats]{dist}}) giving the Hellinger distance between every
#'   pair of rows of \code{P}.
#'
#' @details
#' Rows are rescaled to sum to 1, and tiny negative values (numerical noise
#' from upstream computation) are clamped to zero before rescaling. The
#' Hellinger distance between two probability vectors \eqn{p} and \eqn{q} is
#' \eqn{\frac{1}{\sqrt{2}} \lVert \sqrt{p} - \sqrt{q} \rVert_2}, which is
#' bounded between 0 and 1 and, unlike KL divergence, is a proper metric
#' (symmetric and satisfies the triangle inequality).
#'
#' @export
#'
#' @examples
#' # Three items' membership probabilities across four categories
#' P <- matrix(
#'   c(0.7, 0.1, 0.1, 0.1,
#'     0.6, 0.2, 0.1, 0.1,
#'     0.1, 0.1, 0.1, 0.7),
#'   nrow = 3, byrow = TRUE
#' )
#' hellinger_dist(P)
hellinger_dist <- function(P) {
  P <- as.matrix(P)

  if (any(P < -1e-12)) {
    stop("Profiles contain negative values.")
  }

  # Remove tiny negative numerical errors
  P[P < 0] <- 0

  # Ensure rows sum to one
  P <- P / rowSums(P)

  stats::dist(sqrt(P)) / sqrt(2)
}
