#' Effective (numerical) rank of a matrix
#'
#' Computes the numerical rank of a matrix after centering its columns, by
#' counting singular values that exceed a machine-precision-scaled tolerance.
#'
#' @param M Numeric matrix (or object coercible to one), rows = items,
#'   columns = dimensions.
#'
#' @return Integer giving the number of singular values of the centered
#'   matrix that exceed the tolerance
#'   \code{max(dim(M)) * max(singular values) * .Machine$double.eps}.
#'
#' @details
#' \code{M} is column-centered before computing its singular value
#' decomposition, so the returned rank reflects variance structure rather
#' than an offset from the origin. This is useful for checking how many
#' dimensions of an embedding actually carry signal — for example, an
#' embedding fit with \code{d = 8} dimensions may have an effective rank of
#' only 4 if four dimensions are numerically flat.
#'
#' @export
#'
#' @examples
#' # A matrix with two genuinely independent columns and a third that is a
#' # linear combination of the first two has rank 2, not 3.
#' set.seed(1)
#' a <- rnorm(20)
#' b <- rnorm(20)
#' M <- cbind(a, b, 2 * a - b)
#' matrix_rank(M)
matrix_rank <- function(M) {
  M_centered <- scale(
    as.matrix(M),
    center = TRUE,
    scale = FALSE
  )

  d <- svd(M_centered, nu = 0, nv = 0)$d
  tol <- max(dim(M_centered)) * max(d) * .Machine$double.eps

  sum(d > tol)
}
