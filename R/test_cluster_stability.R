#' Test how stable a hierarchical-clustering partition is under resampling
#'
#' Given a participant-by-participant distance matrix and a chosen number of
#' clusters \code{k} (e.g. from \code{\link{test_for_clusters}}'s
#' \code{best_g}, or any \code{k} you're using with
#' \code{\link[stats]{cutree}}), repeatedly refits the same
#' \code{\link[stats]{hclust}}/\code{\link[stats]{cutree}} pipeline on random
#' subsamples of participants and compares each resampled partition back to
#' the full-data partition. A partition that reflects real structure should
#' reappear reliably across resamples; a partition that happens to look clean
#' in one fit but doesn't survive resampling is more likely to be fitting
#' this particular sample's noise, however interpretable the story attached
#' to it feels.
#'
#' @param dist_mat A participant-by-participant distance matrix (or a
#'   \code{dist} object), e.g. as returned by \code{\link{get.rep.dist}}.
#' @param k Integer. The number of clusters to cut the tree into (must be at
#'   least 2 and leave enough participants per resample -- see
#'   \code{subsample_frac}).
#' @param method Linkage method passed to \code{\link[stats]{hclust}}.
#'   Default \code{"ward.D"}, matching the convention used elsewhere in this
#'   package (e.g. \code{\link{pacc.by.cluster}}'s example,
#'   \code{\link{get.group.list.mean}}'s example).
#' @param n_reps Integer. Number of resamples. Default 500.
#' @param subsample_frac Numeric in (0, 1). Fraction of participants kept in
#'   each resample (drawn without replacement). Default 0.8. Must leave more
#'   than \code{k} participants per resample.
#' @param seed Integer or \code{NULL}. Random seed for the resampling.
#'   Default \code{NULL} leaves the global random state untouched.
#' @param verbose Logical. Print an interpretive summary? Default \code{TRUE}.
#'
#' @section Why resampling rather than another internal quality metric:
#' The Hopkins statistic, BIC, and silhouette index (see
#' \code{\link{test_for_clusters}}) all evaluate a clustering against some
#' assumption about cluster shape (spherical, elliptical-Gaussian, etc.), so
#' disagreement between them often just reflects that the true structure
#' doesn't cleanly match any one of those idealized shapes -- it doesn't
#' resolve which, if any, clustering is trustworthy. A partition that
#' "makes sense" on inspection is also weak evidence on its own: with a
#' modest number of participants, a plausible-sounding story can usually be
#' told about almost any split after the fact. Resampling stability instead
#' asks a question that doesn't depend on cluster shape or a subjective
#' read of the result: if the data collection were repeated (approximated
#' here by holding out a random subset of participants each time), would
#' the same grouping of people reappear? This is a necessary condition for
#' a partition to reflect real, sample-independent structure, though (like
#' any single diagnostic here) not by itself sufficient -- the strongest
#' validation remains an external variable, not used to build the
#' clustering, that the partition predicts.
#'
#' @section Adjusted Rand Index:
#' Each resample's partition is compared to the full-data partition
#' (restricted to the resampled participants) via
#' \code{\link[mclust]{adjustedRandIndex}}, which is 1 for identical
#' partitions, approximately 0 for agreement no better than a random
#' relabeling, and can go negative for agreement systematically worse than
#' chance. \code{mean_ari}/\code{median_ari} summarize this across all
#' \code{n_reps} resamples.
#'
#' @section What "stable" does and doesn't mean:
#' This function tests whether \emph{this specific sample's} partition
#' keeps reappearing when a subset of it is resampled -- it does not test
#' whether the underlying population actually has cluster structure (that
#' is what \code{\link{test_for_clusters}}'s Hopkins statistic is for). A
#' clumpy-looking split that arose purely by chance in one finite sample
#' can still resample as highly stable, because subsampling mostly repeats
#' the same fixed points rather than redrawing new ones. Concretely: in
#' checks on purely random, structure-free data during development, mean
#' ARI averaged around 0.67 at n = 20 and around 0.38 at n = 60 (individual
#' draws ranging from about 0.2 to 0.85) -- noticeably far from the 0 you
#' might expect for "no real clusters," and worse at smaller n, echoing the
#' small-n false-positive pattern already documented for
#' \code{\link{test_for_clusters}}'s BIC comparison. Treat a high
#' \code{mean_ari} as evidence a partition survives resampling, not as
#' evidence it reflects genuine population structure on its own --
#' interpret it together with a significant Hopkins result, and treat an
#' external, independently-measured correlate of cluster membership as the
#' strongest available validation.
#'
#' @return A list with elements:
#' \describe{
#'   \item{\code{ari}}{Numeric vector of length \code{n_reps}: the Adjusted
#'     Rand Index between each resampled partition and the full-data
#'     partition (see \emph{Adjusted Rand Index} above).}
#'   \item{\code{mean_ari}, \code{median_ari}}{Mean and median of
#'     \code{ari}.}
#'   \item{\code{participant_stability}}{Named numeric vector (one entry per
#'     participant, named from \code{dist_mat}'s labels if present):
#'     for each participant, the fraction of same-resample pairwise
#'     co-clustering decisions (same cluster vs. different cluster, against
#'     every other participant who happened to be resampled alongside them)
#'     that agreed with the full-data partition, averaged over every
#'     resample that included them. Lower values flag participants whose
#'     cluster assignment is the least reproducible -- not necessarily
#'     wrong, but the most sensitive to exactly which other participants
#'     happen to be in the sample.}
#'   \item{\code{orig_labels}}{Named integer vector: the full-data
#'     \code{cutree(hclust(dist_mat, method), k)} partition being tested,
#'     for reference.}
#'   \item{\code{k}, \code{n_reps}, \code{subsample_frac}, \code{method}}{
#'     The arguments used, echoed back for traceability.}
#' }
#'
#' @importFrom stats hclust cutree as.dist median
#'
#' @export
#'
#' @examples
#' \dontrun{
#' repdist <- get.rep.dist(icon_emb_ind)
#' clusters <- test_for_clusters(repdist, max_clusters = 3)
#' test_cluster_stability(repdist, k = clusters$best_g)
#' }
test_cluster_stability <- function(dist_mat, k, method = "ward.D", n_reps = 500,
                                    subsample_frac = 0.8, seed = NULL, verbose = TRUE) {
  if (!requireNamespace("mclust", quietly = TRUE)) {
    stop("The 'mclust' package is required (for adjustedRandIndex()). Install it with install.packages('mclust').")
  }

  ## ---- Check arguments / prep distance matrix ----
  d <- stats::as.dist(dist_mat)
  n <- attr(d, "Size")
  if (n < 4) stop("Need at least 4 participants (rows/cols of dist_mat).")
  if (k < 2 || k >= n) stop("k must be between 2 and n - 1 (", n - 1, ").")
  if (subsample_frac <= 0 || subsample_frac >= 1) {
    stop("subsample_frac must be strictly between 0 and 1.")
  }

  full_mat <- as.matrix(d)
  labs <- attr(d, "Labels")
  if (is.null(labs)) labs <- as.character(seq_len(n))

  m <- max(2, round(subsample_frac * n))
  if (m <= k) {
    stop(sprintf(
      "subsample_frac = %.2f leaves only %d participants per resample, not enough for k = %d clusters. Increase subsample_frac.",
      subsample_frac, m, k
    ))
  }

  ## ---- Full-data partition being tested ----
  hc0 <- stats::hclust(d, method = method)
  orig_labels <- stats::cutree(hc0, k)
  names(orig_labels) <- labs

  ## ---- Resampling loop ----
  if (!is.null(seed)) set.seed(seed)

  ari <- numeric(n_reps)
  agree_sum <- numeric(n)
  agree_n <- numeric(n)

  for (b in seq_len(n_reps)) {
    idx <- sample(n, m)
    sub_mat <- full_mat[idx, idx]
    hc_b <- stats::hclust(stats::as.dist(sub_mat), method = method)
    sub_labels <- stats::cutree(hc_b, k)
    orig_sub <- orig_labels[idx]

    ari[b] <- mclust::adjustedRandIndex(sub_labels, orig_sub)

    # Pairwise co-clustering agreement: for every pair of resampled
    # participants, did "same cluster vs. different cluster" agree between
    # the resampled partition and the full-data partition? Accumulated per
    # participant (each row of the m x m agreement matrix) so participants
    # who are frequently mis-grouped relative to the full-data partition
    # can be identified individually, not just summarized as one ARI value.
    same_orig <- outer(orig_sub, orig_sub, `==`)
    same_sub <- outer(sub_labels, sub_labels, `==`)
    agree <- same_orig == same_sub
    diag(agree) <- NA
    agree_sum[idx] <- agree_sum[idx] + rowSums(agree, na.rm = TRUE)
    agree_n[idx] <- agree_n[idx] + (m - 1)
  }

  participant_stability <- agree_sum / agree_n
  names(participant_stability) <- labs

  mean_ari <- mean(ari)
  median_ari <- stats::median(ari)

  if (verbose) {
    cat(sprintf("Resampling stability of the k = %d partition (%s linkage):\n", k, method))
    cat(sprintf(
      "  %d resamples, %.0f%% of participants per resample (m = %d of %d)\n",
      n_reps, 100 * subsample_frac, m, n
    ))
    cat(sprintf(
      "Adjusted Rand Index vs. full-data partition: mean = %.3f, median = %.3f\n",
      mean_ari, median_ari
    ))
    cat(if (mean_ari > 0.75) {
      "  -> highly stable: resampled partitions closely reproduce the full-data clustering\n"
    } else if (mean_ari > 0.4) {
      "  -> moderately stable: partition reproduces above chance, but with real disagreement across resamples\n"
    } else {
      "  -> unstable: resampled partitions are not much more consistent with the full-data clustering than chance\n"
    })
    n_show <- min(3, n)
    least_stable <- sort(participant_stability)[seq_len(n_show)]
    cat(sprintf("Least stable participant%s (lowest co-clustering agreement across resamples):\n",
                if (n_show > 1) "s" else ""))
    print(round(least_stable, 3))
  }

  invisible(list(
    ari = ari,
    mean_ari = mean_ari,
    median_ari = median_ari,
    participant_stability = participant_stability,
    orig_labels = orig_labels,
    k = k,
    n_reps = n_reps,
    subsample_frac = subsample_frac,
    method = method
  ))
}
