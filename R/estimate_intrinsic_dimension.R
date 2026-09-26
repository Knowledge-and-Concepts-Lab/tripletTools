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
#' @section A known weakness for a single dominant dimension:
#' Horn's parallel analysis is well documented to be conservative at rank 1
#' specifically, and this can be severe enough that \emph{even an obvious,
#' dominant true dimension fails to clear its own threshold} -- not just a
#' borderline one. The reason: permutation preserves each column's own
#' variance exactly (only scrambling which participant has which value), so
#' when nearly all the real signal is concentrated in one dimension, the
#' permutation null's own top eigenvalue is built largely from that same
#' large variance, plus a small extra upward bias from incidental
#' correlations among the now-independent shuffled columns. In effect, the
#' leading dimension has to "beat a shuffled version of itself" -- a bar
#' that stays hard to clear regardless of how strong the true signal
#' actually is. When this happens, \code{k} is floored at 1 (see
#' \code{forced_to_one} below) rather than allowed to drop to 0, but that
#' floor is a default, not a detection -- \code{dominance_ratio} (also
#' below) is provided specifically to help tell apart "this floor is very
#' likely masking a real dominant dimension" from "this floor reflects a
#' genuine absence of detectable structure," and \code{verbose} output
#' spells out which case applies when \code{forced_to_one} is \code{TRUE}.
#' Corroborating evidence independent of this test (e.g. a reproducible
#' \code{hclust} split, or \code{\link{test_for_clusters}}'s BIC) is the
#' most reliable way to resolve the ambiguity.
#'
#' @return A list with elements:
#' \describe{
#'   \item{\code{k}}{Estimated number of real dimensions (integer, at least 1).}
#'   \item{\code{eigenvalues}}{Observed eigenvalue for every candidate dimension.}
#'   \item{\code{null_threshold}}{The permutation-based cutoff at each rank
#'     (same length as \code{eigenvalues}).}
#'   \item{\code{n_permutations}}{As supplied.}
#'   \item{\code{forced_to_one}}{Logical: \code{TRUE} if \code{k} is the
#'     floored default (not even the leading dimension passed) rather than
#'     an actual detection -- see \emph{A known weakness for a single
#'     dominant dimension} above.}
#'   \item{\code{dominance_ratio}}{Numeric, or \code{NA} if there was only
#'     one candidate dimension to begin with. The leading eigenvalue
#'     divided by the mean of the rest -- a large value (rule of thumb:
#'     above about 3) alongside \code{forced_to_one = TRUE} suggests the
#'     floor is likely masking a real dominant dimension rather than
#'     reflecting an honest absence of structure (see above).}
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

  # When forced_to_one, distinguish "the data has essentially no detectable
  # multivariate structure" from "there's an obvious dominant dimension, but
  # Horn's parallel analysis is conservative for exactly this case" (see
  # dominance_ratio's docs below for why). A large ratio here doesn't prove
  # dimension 1 is real, but it's a strong, easy-to-compute hint that the
  # forced floor is likely masking real structure rather than reporting an
  # honest absence of it.
  dominance_ratio <- if (k_candidate > 1) real_eig[1] / mean(real_eig[-1]) else NA_real_

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
      if (!is.na(dominance_ratio) && dominance_ratio > 3) {
        cat(sprintf(
          paste(
            "This is likely a false negative rather than a genuine absence of structure:",
            "the leading eigenvalue (%.3g) is about %.1fx the typical size of the rest",
            "(%.3g), suggesting one real dominant dimension. Horn's parallel analysis is",
            "known to be conservative for exactly this case: when nearly all the real",
            "signal is concentrated in a single factor, the permutation null preserves",
            "each column's own variance (only scrambling which participant has which",
            "value), so the null's own top eigenvalue ends up built largely from that",
            "same dominant variance -- the leading dimension effectively has to 'beat a",
            "shuffled version of itself,' a bar that's unusually hard to clear regardless",
            "of how strong the true signal is. Corroborate with independent evidence",
            "(e.g. a reproducible hclust split, or test_for_clusters()'s BIC) before",
            "concluding there's no real structure here.\n"
          ),
          real_eig[1], dominance_ratio, mean(real_eig[-1])
        ))
      } else {
        cat("No leading dimension stood out as dominant enough to suggest this is just",
            "Horn's single-dominant-factor conservatism (see the function's",
            "documentation) -- here, k = 1 is closer to a genuine floor default than a",
            "likely-real detection, and the data may have little detectable",
            "multivariate structure.\n")
      }
    }
    cat(sprintf("-> estimated intrinsic dimension: %d\n", k))
  }

  invisible(list(
    k = k,
    eigenvalues = real_eig,
    null_threshold = null_threshold,
    n_permutations = n_permutations,
    forced_to_one = forced_to_one,
    dominance_ratio = dominance_ratio
  ))
}
