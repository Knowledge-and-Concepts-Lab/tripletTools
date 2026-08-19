#' Spectral similarity between two matrices' variance structure
#'
#' Computes the cosine similarity between the singular-value spectra of two
#' matrices, as a rotation-independent proxy for how similar their variance
#' structure is.
#'
#' @param candidate Numeric matrix, rows = items, columns = dimensions.
#' @param target Numeric matrix, rows = items, columns = dimensions.
#'   \code{candidate} and \code{target} need not have the same number of
#'   columns.
#'
#' @return A single number between 0 and 1: the cosine similarity between
#'   the (zero-padded) singular value vectors of \code{candidate} and
#'   \code{target}.
#'
#' @details
#' Each matrix is column-centered and its singular values extracted via SVD.
#' The shorter singular-value vector is zero-padded to match the length of
#' the longer one, and the cosine similarity between the two vectors is
#' returned.
#'
#' Because this compares only the spectra (not the aligned coordinates
#' themselves), it does not require \code{candidate} and \code{target} to
#' share the same dimensionality or item ordering alignment the way an
#' actual Procrustes fit (e.g. \code{\link{get.rep.dist}}) does — it asks
#' only whether the two embeddings distribute variance across dimensions in
#' a similar way. A value near 1 means the two matrices have a similarly
#' shaped variance profile (e.g. both dominated by one or two dimensions);
#' it does not by itself mean the embeddings are otherwise similar.
#'
#' @export
#'
#' @examples
#' set.seed(1)
#' # Two matrices with similarly shaped (but not identical) spectra
#' candidate <- cbind(rnorm(20, sd = 4), rnorm(20, sd = 1))
#' target    <- cbind(rnorm(20, sd = 5), rnorm(20, sd = 1.2), rnorm(20, sd = 0.1))
#' procrustes_spectral_ceiling(candidate, target)
procrustes_spectral_ceiling <- function(candidate, target) {

  center_matrix <- function(M) {
    scale(as.matrix(M), center = TRUE, scale = FALSE)
  }

  a <- svd(center_matrix(candidate), nu = 0, nv = 0)$d
  b <- svd(center_matrix(target),    nu = 0, nv = 0)$d

  n <- max(length(a), length(b))
  length(a) <- n
  length(b) <- n

  a[is.na(a)] <- 0
  b[is.na(b)] <- 0

  sum(a * b) / sqrt(sum(a^2) * sum(b^2))
}
