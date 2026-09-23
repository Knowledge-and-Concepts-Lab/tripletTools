#' Estimate how many dimensions of a distance matrix reflect real structure
#'
#' Given a participant-by-participant distance matrix (e.g. from
#' \code{\link{get.rep.dist}}), estimates how many of its classical-MDS
#' dimensions carry genuine multivariate structure, as opposed to
#' individual-level noise that inflates every dimension's eigenvalue away
#' from exactly zero without necessarily reflecting any real, reproducible
#' pattern. Used by \code{\link{test_for_clusters}} to choose \code{k_use}
#' when it isn't supplied directly.
#'
#' @param dist_mat A participant-by-participant distance matrix (or a
#'   \code{dist} object), e.g. as returned by \code{\link{get.rep.dist}}.
#' @param n_permutations Integer. Number of column-permuted null datasets
#'   used to build the reference distribution at each rank. Default 200.
#' @param threshold_quantile Numeric in (0, 1). A dimension is retained
#'   only if its observed eigenvalue exceeds this quantile of the
#'   permutation-null eigenvalues at the same rank. Default 0.95.
#' @param seed Integer or \code{NULL}. Random seed for the permutations.
#'   Default \code{NULL} leaves the global random state untouched.
#' @param verbose Logical. Print an interpretive summary? Default \code{TRUE}.
#'
#' @section Method:
#' This is Horn's parallel analysis (Horn, 1965), applied to the classical
#' MDS decomposition of \code{dist_mat} rather than to raw variables
#' directly -- a standard approach for choosing the number of meaningful
#' ordination axes from a distance/dissimilarity matrix (see Peres-Neto,
#' Jackson & Somers, 2005, for a review of this and related stopping
#' rules). \code{dist_mat} is first converted to coordinates via classical
#' MDS (\code{\link[stats]{cmdscale}}), retaining every dimension with a
#' numerically nonzero eigenvalue as the candidate pool. For
#' \code{n_permutations} iterations, each coordinate column is
#' independently permuted across participants -- destroying any real,
#' participant-identity-linked covariation between dimensions while
#' preserving each dimension's own marginal spread -- and the resulting
#' matrix's covariance eigenvalues are recorded. A dimension is judged
#' "real" only if its observed eigenvalue exceeds \code{threshold_quantile}
#' of the permuted eigenvalues at that same rank; \code{k} is the largest
#' number of leading dimensions that all clear this bar, scanning from the
#' top and stopping at the first dimension that doesn't.
#'
#' Unlike a numerical-rank tolerance (dropping only eigenvalues that are
#' zero up to floating-point roundoff -- which is what
#' \code{\link{matrix_rank}} does, and what this function's candidate pool
#' still uses as an initial ceiling) or a fixed total-variance-explained
#' threshold, this adapts to the actual noise level in the data: a
#' dimension carrying only per-participant noise will generally look
#' statistically indistinguishable from its own permuted version, however
#' numerically nonzero its eigenvalue is. Observed eigenvalues are
#' recomputed from \code{coords}' own covariance matrix (rather than taken
#' directly from \code{cmdscale}'s output) so the "real" side of the
#' comparison is on the exact same scale as the permuted side -- both go
#' through the same \code{cov()} then \code{eigen()} pipeline.
#'
#' @return A list with elements:
#' \describe{
#'   \item{\code{k}}{Estimated number of real dimensions (integer, at least 1).}
#'   \item{\code{eigenvalues}}{Observed eigenvalue for every candidate dimension.}
#'   \item{\code{null_threshold}}{The permutation-based cutoff at each rank
#'     (same length as \code{eigenvalues}).}
#'   \item{\code{n_permutations}}{As supplied.}
#' }
#'
#' @importFrom stats cmdscale cov quantile as.dist
#'
#' @export
#'
#' @examples
#' \dontrun{
#' repdist <- get.rep.dist(icon_emb_ind)
#' estimate_intrinsic_dimension(repdist)
#' }
estimate_intrinsic_dimension <- function(dist_mat, n_permutations = 200,
                                          threshold_quantile = 0.95, seed = NULL,
                                          verbose = TRUE) {
  d <- stats::as.dist(dist_mat)
  n <- attr(d, "Size")
  if (n < 4) stop("Need at least 4 participants (rows/cols of dist_mat).")
  if (n_permutations < 1) stop("n_permutations must be at least 1.")
  if (threshold_quantile <= 0 || threshold_quantile >= 1) {
    stop("threshold_quantile must be strictly between 0 and 1.")
  }

  ## ---- Candidate pool: classical MDS, numerical-rank ceiling ----
  k_request <- n - 2
  cmd <- suppressWarnings(stats::cmdscale(d, k = k_request, eig = TRUE))
  tol <- length(cmd$eig) * max(cmd$eig) * .Machine$double.eps
  n_pos <- sum(cmd$eig > tol)
  k_candidate <- max(1, min(k_request, n_pos))
  coords <- cmd$points[, seq_len(k_candidate), drop = FALSE]

  ## ---- Observed eigenvalues, on the same cov()/eigen() scale used below ----
  real_eig <- eigen(stats::cov(coords), symmetric = TRUE, only.values = TRUE)$values

  ## ---- Permutation null: column-permute coords, recompute eigenvalues ----
  if (!is.null(seed)) set.seed(seed)
  null_eig <- matrix(NA_real_, n_permutations, k_candidate)
  for (p in seq_len(n_permutations)) {
    perm_coords <- apply(coords, 2, sample)
    null_eig[p, ] <- eigen(stats::cov(perm_coords), symmetric = TRUE, only.values = TRUE)$values
  }
  null_threshold <- apply(null_eig, 2, stats::quantile, probs = threshold_quantile)

  ## ---- k: scan from the top, stop after two CONSECUTIVE failures ----
  # Neither pure alternative works well: stopping at the very first failure
  # is vulnerable to Horn's parallel analysis's well-documented rank-1
  # conservatism (the top component's null threshold is itself the maximum
  # of many correlated quantities, so it's an inflated order statistic --
  # verified empirically here, unchanged across n_permutations from 100 to
  # 2000, so more permutations alone doesn't fix it). But taking the
  # highest-ever-passing rank is *too* permissive: testing ~10-20 ranks
  # each at a 95% threshold means roughly one false positive among purely
  # noise ranks is expected by chance alone, and a single high-rank false
  # positive then inflates k all the way up to it (verified empirically: on
  # pure-noise and many-noise-dimension test data, this pushed k to the
  # full candidate ceiling). Requiring two consecutive failures before
  # stopping tolerates one isolated noisy miss (fixing the rank-1 issue,
  # since a real dimension right after it resets the failure streak)
  # without chasing an isolated false positive arbitrarily far out (an
  # isolated pass amid otherwise-failing ranks only pulls k up to that one
  # rank, not past the next two failures).
  passed <- real_eig > null_threshold
  last_pass <- 0
  fail_streak <- 0
  for (i in seq_along(passed)) {
    if (passed[i]) {
      last_pass <- i
      fail_streak <- 0
    } else {
      fail_streak <- fail_streak + 1
      if (fail_streak >= 2) break
    }
  }
  k <- max(1, last_pass)
  forced_to_one <- last_pass == 0

  if (verbose) {
    cat("Observed vs. permutation-null eigenvalues (kept = observed > threshold):\n")
    print(data.frame(
      dim       = seq_len(k_candidate),
      observed  = round(real_eig, 4),
      threshold = round(null_threshold, 4),
      kept      = real_eig > null_threshold
    ))
    if (forced_to_one) {
      cat("Note: not even the leading dimension exceeded its permutation threshold;",
          "k forced to the minimum of 1 rather than 0.\n")
    }
    cat(sprintf("-> estimated intrinsic dimension: %d\n", k))
  }

  invisible(list(
    k = k,
    eigenvalues = real_eig,
    null_threshold = null_threshold,
    n_permutations = n_permutations
  ))
}
