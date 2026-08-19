#' Variance captured by the top k dimensions of a target matrix
#'
#' Computes the fraction of a matrix's total variance (sum of squared
#' singular values, after centering) that is captured by its top \code{k}
#' singular values.
#'
#' @param target Numeric matrix, rows = items, columns = dimensions.
#' @param k Number of leading dimensions to retain. Must be at least 1.
#'
#' @return A single number between 0 and 1: the square root of the ratio of
#'   the summed squared top-\code{k} singular values to the summed squared
#'   singular values overall.
#'
#' @details
#' \code{target} is column-centered before computing its singular value
#' decomposition (matching how \code{vegan::procrustes} centers its inputs),
#' and singular values that are numerically zero are dropped before ranking.
#' If \code{k} exceeds the number of nonzero singular values, all of them are
#' used.
#'
#' This gives an upper bound — a "ceiling" — on how well a \code{k}-dimensional
#' embedding could ever recover \code{target}'s structure under a Procrustes
#' fit, independent of any particular candidate embedding: even a perfect
#' \code{k}-dimensional candidate cannot exceed this value, because it is a
#' property of \code{target} alone. Compare a real candidate embedding's
#' Procrustes correlation against this ceiling to judge how much of the
#' achievable structure it actually captures.
#'
#' @export
#'
#' @examples
#' set.seed(1)
#' # A target matrix whose variance is concentrated in its first two columns
#' target <- cbind(rnorm(20, sd = 5), rnorm(20, sd = 3), rnorm(20, sd = 0.1))
#' procrustes_rank_ceiling(target, k = 2)
procrustes_rank_ceiling <- function(target, k) {

  target <- as.matrix(target)

  if (!is.numeric(target)) {
    stop("target must be numeric.")
  }

  if (anyNA(target)) {
    stop("target contains missing values.")
  }

  if (k < 1L) {
    stop("k must be at least 1.")
  }

  # vegan::procrustes centers each column
  Y <- scale(target, center = TRUE, scale = FALSE)

  singular_values <- svd(Y, nu = 0, nv = 0)$d

  # Remove numerically zero singular values
  tolerance <- max(dim(Y)) * max(singular_values) * .Machine$double.eps
  singular_values <- singular_values[singular_values > tolerance]

  k <- min(k, length(singular_values))

  sqrt(
    sum(singular_values[seq_len(k)]^2) /
      sum(singular_values^2)
  )
}
