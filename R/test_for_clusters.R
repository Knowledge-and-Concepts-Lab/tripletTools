#' Test whether embeddings show any cluster structure at all
#'
#' Given a participant-by-participant distance matrix (e.g. from
#' \code{\link{get.rep.dist}}), tests whether the data show any cluster
#' structure at all -- a different question from "how many clusters,"
#' which methods like the silhouette index only address for k >= 2 and
#' implicitly assume that splitting into groups is worthwhile in the first
#' place.
#'
#' @param dist_mat A participant-by-participant distance matrix (or a
#'   \code{dist} object), e.g. as returned by \code{\link{get.rep.dist}}.
#' @param max_clusters Integer. Maximum number of clusters to consider for
#'   the BIC comparison (the G = 1, "no clusters" baseline is always
#'   included in addition). Default 5. Must be less than the number of
#'   participants.
#' @param k_use Integer or \code{NULL}. Number of classical-MDS dimensions
#'   to use for both the Hopkins statistic and the BIC comparison. Default
#'   \code{NULL} estimates it automatically via
#'   \code{\link{estimate_intrinsic_dimension}} -- see \emph{Dimensionality
#'   reduction} below for why this matters far more than it might seem.
#'   Pass an integer to bypass estimation and use a fixed number of
#'   dimensions directly (must be between 1 and the number of usable cMDS
#'   dimensions).
#' @param m Integer or \code{NULL}. Number of points used for the Hopkins
#'   statistic (see \emph{Hopkins statistic} below). Default \code{NULL}
#'   uses every participant rather than a random subsample, since the
#'   usual motivation for subsampling (large datasets) rarely applies to
#'   the modest participant counts this function is meant for, and
#'   subsampling would just add unnecessary noise on top of an already
#'   small sample.
#' @param seed Integer or \code{NULL}. Random seed for the synthetic
#'   uniform points the Hopkins statistic compares against. Default
#'   \code{NULL} leaves the global random state untouched.
#' @param verbose Logical. Print an interpretive summary? Default \code{TRUE}.
#'
#' @section Dimensionality reduction:
#' Both the Hopkins statistic and the BIC comparison need actual
#' coordinates, not just a distance matrix, so \code{dist_mat} is first
#' converted to coordinates via classical MDS (\code{\link[stats]{cmdscale}}).
#' The number of dimensions retained for that coordinate representation
#' turns out to matter a great deal -- far more than it might seem, since
#' it isn't just a summary-for-visualization choice the way it looks at
#' first. With realistic individual-level noise (i.e. essentially any real
#' representational-distance matrix), every dimension's eigenvalue gets
#' pushed measurably away from zero, so a purely numerical rank check
#' retains nearly every available dimension (up to \code{n - 2}) almost
#' regardless of how many dimensions actually carry real signal -- and the
#' more of those noise-only dimensions get included, the harder it becomes
#' for a nearest-neighbor statistic like Hopkins to detect real structure
#' amid them (a real 2-cluster effect that was easily detectable at a
#' correctly-chosen small \code{k} became statistically invisible once
#' every positive-eigenvalue dimension was retained, verified empirically
#' during development on real, not synthetic, data). \code{k_use} controls
#' this directly: leave it \code{NULL} to estimate it via
#' \code{\link{estimate_intrinsic_dimension}}'s permutation-based approach
#' (distinguishing dimensions with real, reproducible structure from ones
#' that only look nonzero because of ordinary noise), or supply it directly
#' to bypass estimation. If a nontrivial fraction of the total eigenvalue
#' magnitude is negative (i.e. \code{dist_mat} isn't well approximated by
#' any Euclidean configuration), a warning is issued; consider
#' \code{cmdscale(dist_mat, add = TRUE)}'s Cailliez correction in that case.
#'
#' @section Hopkins statistic:
#' Compares nearest-neighbor distances among the real (cMDS-derived)
#' points to nearest-neighbor distances from synthetic points generated
#' uniformly at random within the same coordinate ranges, \strong{both
#' measured within the same \code{k_use}-dimensional coordinate space} --
#' an earlier version of this function computed the real-to-real distances
#' from the original, untruncated \code{dist_mat} instead, which silently
#' deflated the synthetic-to-real distances relative to the real-to-real
#' ones whenever \code{k_use} was less than the full reconstructing
#' dimensionality, dragging \code{H} toward "less clustered than random"
#' as an artifact of truncation itself, regardless of whether the dropped
#' dimensions were signal or noise (this is what made a naive fixed small
#' \code{k_use} look harmful before the fix, when it was actually the
#' truncation-vs-full-space mismatch that was harmful):
#' \eqn{H = \sum w_i / (\sum u_i + \sum w_i)}, where \eqn{u_i} are
#' real-to-real nearest-neighbor distances and \eqn{w_i} are
#' synthetic-to-real nearest-neighbor distances (the simple, unweighted
#' ratio, as commonly implemented in software -- some presentations instead
#' raise distances to the power of the dimensionality, which is more
#' faithful to the statistic's original derivation but numerically fragile
#' once dimensionality is more than modest). \eqn{H} near 0.5 indicates no
#' detectable clustering; values approaching 1 indicate strong clustering
#' tendency. Under the null of complete spatial randomness, \eqn{H} is
#' approximately \eqn{Beta(m, m)}-distributed (a commonly used
#' approximation, not an exact finite-sample result), giving the
#' approximate one-sided p-value for "H > 0.5" returned as
#' \code{hopkins_p_value}.
#'
#' @section BIC over number of clusters:
#' Fits Gaussian mixture models for G = 1 (i.e. no sub-clusters) through
#' \code{max_clusters} via \code{\link[mclust]{mclustBIC}} (requires the
#' \pkg{mclust} package), taking the best (over covariance-structure model
#' types) BIC at each G. Reported in the standard statistical convention
#' (\strong{lower is better}) -- note this is the opposite sign from what
#' \pkg{mclust} reports internally, where higher is better; values here
#' have been negated accordingly, so "most likely number of clusters"
#' always means "minimizes this vector," matching ordinary BIC-based model
#' selection. A G with no feasible model fit (only possible for larger G
#' relative to a small number of participants) is reported as \code{NA}.
#'
#' \strong{This BIC comparison is noticeably less reliable than the Hopkins
#' statistic at small-to-moderate sample sizes.} In a simulation over
#' purely random (no true clusters) data during development, the BIC-based
#' \code{best_g} spuriously favored more than one cluster in roughly a
#' third of runs at \code{n = 20}, versus essentially never for the
#' Hopkins-based test at the same n; this false-positive rate fell to
#' roughly 5-10\% by \code{n = 60}. This is a real limitation of searching
#' over many (G, covariance-structure) model combinations via BIC at small
#' n, not a bug -- treat \code{best_g} as considerably less trustworthy
#' than \code{hopkins}/\code{hopkins_p_value} when the number of
#' participants is small, and prefer the Hopkins-based conclusion if the
#' two disagree.
#'
#' @return A list with elements:
#' \describe{
#'   \item{\code{hopkins}}{The Hopkins statistic (numeric, in \eqn{[0,1]}).}
#'   \item{\code{bic}}{Named numeric vector of length \code{max_clusters},
#'     the BIC (lower is better) for \code{G = 1, ..., max_clusters}.}
#'   \item{\code{hopkins_p_value}}{Approximate one-sided p-value for
#'     \code{hopkins > 0.5} (see \emph{Hopkins statistic} above).}
#'   \item{\code{best_g}}{The number of clusters minimizing \code{bic}.}
#'   \item{\code{k_use}}{The number of cMDS dimensions actually used --
#'     either the supplied \code{k_use} or the value estimated by
#'     \code{\link{estimate_intrinsic_dimension}}, so results stay
#'     traceable without needing to rerun the estimation separately.}
#' }
#'
#' @importFrom stats cmdscale runif pbeta as.dist dist
#'
#' @export
#'
#' @examples
#' \dontrun{
#' repdist <- get.rep.dist(icon_emb_ind)
#' test_for_clusters(repdist, max_clusters = 3)
#' }
test_for_clusters <- function(dist_mat, max_clusters = 5, k_use = NULL, m = NULL,
                               seed = NULL, verbose = TRUE) {
  if (!requireNamespace("mclust", quietly = TRUE)) {
    stop("The 'mclust' package is required. Install it with install.packages('mclust').")
  }

  ## ---- Check arguments / prep distance matrix ----
  d <- stats::as.dist(dist_mat)
  n <- attr(d, "Size")
  if (n < 4) stop("Need at least 4 participants (rows/cols of dist_mat).")
  if (max_clusters < 1) stop("max_clusters must be at least 1.")
  if (max_clusters >= n) {
    stop("max_clusters must be less than the number of participants (", n, ").")
  }

  ## ---- Classical MDS: retain every positive-eigenvalue dimension, up to n - 2 ----
  k_request <- n - 2
  cmd <- suppressWarnings(stats::cmdscale(d, k = k_request, eig = TRUE))
  frac_neg_mass <- -sum(cmd$eig[cmd$eig < 0]) / sum(abs(cmd$eig))
  if (frac_neg_mass > 0.05) {
    warning(sprintf(
      "%.0f%% of total eigenvalue magnitude is negative -- dist_mat is not well approximated by a Euclidean configuration. Consider cmdscale(dist_mat, add = TRUE).",
      100 * frac_neg_mass
    ))
  }
  # A naive eig > 0 check counts many numerically-negligible eigenvalues
  # (floating-point noise around a true lower rank, e.g. ~1e-13) as real
  # dimensions. That noise is harmless for the Hopkins statistic but
  # substantially hurts mclust's BIC comparison below, which is far more
  # sensitive to uninformative extra dimensions (verified: on a synthetic,
  # obviously-2-cluster dataset, retaining every nominally-positive
  # dimension spuriously favored G=1, while retaining only the true signal
  # dimensions correctly favored G=2). Using the same relative-tolerance
  # convention as matrix_rank() (elsewhere in this package) fixes this --
  # but applied directly to cmd$eig, not to a fresh SVD of cmd$points:
  # cmdscale() forms points as eigenvectors scaled by sqrt(eigenvalue), and
  # that square root *inflates* the relative size of already-tiny
  # eigenvalues (sqrt shrinks small numbers less than they shrink
  # themselves), which pushed this same noise back above tolerance when
  # re-derived from points instead of applied to cmd$eig directly.
  tol <- length(cmd$eig) * max(cmd$eig) * .Machine$double.eps
  n_pos <- sum(cmd$eig > tol)
  k_max <- max(1, min(k_request, n_pos))

  if (is.null(k_use)) {
    dim_est <- estimate_intrinsic_dimension(dist_mat, seed = seed, verbose = FALSE)
    k_use <- dim_est$k
  } else {
    if (k_use < 1 || k_use > k_max) {
      stop(sprintf(
        "k_use must be between 1 and %d (the number of usable cMDS dimensions), got %d.",
        k_max, k_use
      ))
    }
  }
  coords <- cmd$points[, seq_len(k_use), drop = FALSE]

  ## ---- Hopkins statistic ----
  if (!is.null(seed)) set.seed(seed)
  if (is.null(m)) m <- n

  # u is computed WITHIN the same k_use-dimensional space as w below (see
  # "Hopkins statistic" above for why this matters -- an earlier version
  # computed this from the untruncated dist_mat directly).
  real_dist <- as.matrix(stats::dist(coords))
  diag(real_dist) <- Inf
  idx <- if (m < n) sample(n, m) else seq_len(n)
  u <- apply(real_dist[idx, , drop = FALSE], 1, min) # nearest real-to-real neighbor

  ranges <- apply(coords, 2, range)
  synth <- matrix(
    stats::runif(m * k_use,
                 min = rep(ranges[1, ], each = m),
                 max = rep(ranges[2, ], each = m)),
    nrow = m, ncol = k_use
  )
  w <- apply(synth, 1, function(pt) { # nearest synthetic-to-real neighbor
    min(sqrt(rowSums(sweep(coords, 2, pt)^2)))
  })

  H <- sum(w) / (sum(u) + sum(w))
  hopkins_p <- stats::pbeta(H, m, m, lower.tail = FALSE)

  ## ---- BIC across G = 1..max_clusters via mclust ----
  bic_mat <- mclust::mclustBIC(coords, G = 1:max_clusters, verbose = FALSE)
  raw_bic_per_g <- apply(bic_mat, 1, function(row) {
    if (all(is.na(row))) NA_real_ else max(row, na.rm = TRUE)
  })
  bic <- -raw_bic_per_g # negate: mclust's convention is higher-is-better
  names(bic) <- paste0("G=", seq_len(max_clusters))
  best_g <- unname(which.min(bic))

  if (verbose) {
    cat(sprintf("Dimensions used (k_use): %d\n", k_use))
    cat(sprintf("Hopkins statistic: %.3f (p = %.4g for H0: no clustering)\n", H, hopkins_p))
    cat(if (hopkins_p < 0.05) {
      "  -> evidence of cluster structure (more than one cluster likely)\n"
    } else {
      "  -> no evidence of cluster structure beyond what's expected by chance\n"
    })
    cat("BIC by number of clusters (lower is better):\n")
    print(round(bic, 2))
    cat(sprintf("  -> best supported number of clusters: %d\n", best_g))
  }

  invisible(list(
    hopkins = H,
    bic = bic,
    hopkins_p_value = hopkins_p,
    best_g = best_g,
    k_use = k_use
  ))
}
