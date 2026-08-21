#' Test whether two groups' embeddings differ reliably
#'
#' Fits a separate group embedding for each of two participant groups and
#' measures how well they Procrustes-align, then compares that alignment to
#' a null distribution built by repeatedly re-partitioning the pooled
#' participants at random (preserving the true groups' sizes) and measuring
#' the same alignment between the resulting pseudo-groups. If the true
#' groups align reliably *worse* than random partitions of the same sizes
#' do, that's evidence the groups differ in how they represent the items --
#' beyond what's expected from ordinary between-participant variability
#' alone.
#'
#' @param triplet_list A named list of data frames, one per participant, as
#'   returned by \code{\link{get.combined}}. Names identify participants
#'   (worker IDs).
#' @param group Group membership for each participant: either a named vector
#'   (names = worker IDs matching \code{triplet_list}) or a data frame with
#'   columns \code{worker_id} and \code{group}. Must cover exactly the same
#'   worker IDs as \code{triplet_list}, with exactly two distinct values.
#' @param d Embedding dimensionality, held fixed across every fit (the true
#'   split and every null permutation). Choose this beforehand -- e.g. via
#'   \code{\link{estimate_dimensionality}} on the pooled data -- rather than
#'   re-selecting it per permutation, which would be prohibitively slow and
#'   would also entangle dimensionality selection with the group-difference
#'   test itself.
#' @param n_permutations Number of null (random-partition) replicates.
#'   Default \code{999L}. Each replicate needs 2 full embedding fits, so
#'   this function is compute-heavy -- see \emph{Details} for the
#'   Condor-based companion for larger-scale runs.
#' @param seed Integer random seed for reproducibility, both for the random
#'   participant partitions and (derived per fit) each embedding's own
#'   fitting seed. Default \code{1}.
#' @param max_epochs,tolerance,tol_window,device,geometry,radius,norm_penalty
#'   Forwarded to \code{\link{run_group_embedding_from_list}} for every fit
#'   (the true split and every null permutation).
#' @param verbose Logical. If \code{TRUE} (default), print progress as each
#'   replicate is fit.
#'
#' @return An object of class \code{"group_difference_test"}: a named list
#'   with elements:
#' \describe{
#'   \item{\code{observed_correlation}}{The Procrustes correlation between
#'     the two true groups' embeddings (via \code{\link{get.rep.dist}}).}
#'   \item{\code{null_correlations}}{Numeric vector of length
#'     \code{n_permutations}: the same correlation for each random
#'     same-sized partition of the pooled participants.}
#'   \item{\code{p_value}}{One-sided permutation p-value,
#'     \code{(1 + sum(null_correlations <= observed_correlation)) /
#'     (1 + n_permutations)} -- small when the true groups align reliably
#'     worse than random partitions do.}
#'   \item{\code{settings}}{The arguments this call was made with, plus
#'     \code{group_levels} and \code{group_sizes}.}
#' }
#'
#' @details
#' Null replicates are drawn at the *same sizes* as the true groups (not a
#' blanket 50/50 split), since embedding quality depends on how much data
#' went into it -- comparing an unequal true split against evenly-sized
#' random halves would confound sample-size differences with genuine group
#' differences.
#'
#' This function is meant for small-scale or exploratory use: every
#' replicate (the true split plus each of \code{n_permutations} null
#' partitions) requires two full embedding fits, run serially. For a
#' large-scale run, \code{inst/condor} ships a companion HTCondor workflow
#' (\code{condor_group_diff_workflow.py}) implementing the same procedure
#' (same size-matched null partitioning, same one-sided p-value), dispatched
#' as many independent per-replicate jobs rather than run serially in one R
#' session. The two are independent implementations of the same statistical
#' procedure, not guaranteed to reproduce identical numbers given "the same"
#' seed (participant partitioning uses R's vs. Python's own random number
#' generator) -- only the same logic.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # icon_triplets has 6 participants; split into two groups of 3
#' ids <- names(icon_triplets)
#' group <- setNames(rep(c("A", "B"), each = 3), ids)
#'
#' result <- group_difference_test(
#'   icon_triplets, group, d = 3L,
#'   n_permutations = 99L, max_epochs = 5000L
#' )
#' result$observed_correlation
#' result$p_value
#' }
group_difference_test <- function(
    triplet_list,
    group,
    d,
    n_permutations = 999L,
    seed = 1,
    max_epochs = 50000L,
    tolerance = 1e-4,
    tol_window = 10000L,
    device = NULL,
    geometry = c("euclidean", "sphere"),
    radius = 1,
    norm_penalty = 0,
    verbose = TRUE
) {
  geometry <- match.arg(geometry)

  worker_ids <- names(triplet_list)
  if (is.null(worker_ids) || any(!nzchar(worker_ids))) {
    stop("triplet_list must be a named list (names = participant IDs).")
  }

  if (is.data.frame(group)) {
    if (!all(c("worker_id", "group") %in% names(group))) {
      stop("group, if a data frame, must have columns 'worker_id' and 'group'.")
    }
    group_vec <- stats::setNames(as.character(group$group), as.character(group$worker_id))
  } else {
    group_vec <- group
    if (is.null(names(group_vec))) {
      stop("group must be named by participant ID (or a data frame with worker_id/group columns).")
    }
  }

  if (!setequal(names(group_vec), worker_ids)) {
    stop("group must cover exactly the same participant IDs as triplet_list.")
  }
  group_vec <- group_vec[worker_ids]
  # as.character() on a named vector drops its names -- reassign explicitly
  # rather than relying on it to preserve them.
  group_vec <- stats::setNames(as.character(group_vec), worker_ids)

  group_levels <- unique(group_vec)
  if (length(group_levels) != 2L) {
    stop("group must have exactly two distinct values.")
  }

  n1 <- sum(group_vec == group_levels[1])
  n2 <- sum(group_vec == group_levels[2])

  if (n1 < 3L || n2 < 3L) {
    stop("Each group must contain at least 3 participants.")
  }

  if (d < 1L) {
    stop("d must be at least 1.")
  }

  if (n_permutations < 1L) {
    stop("n_permutations must be at least 1.")
  }

  set.seed(seed)

  fit_one_side <- function(ids, fit_seed) {
    run_group_embedding_from_list(
      triplet_list = triplet_list[ids],
      d            = d,
      max_epochs   = max_epochs,
      tolerance    = tolerance,
      tol_window   = tol_window,
      seed         = fit_seed,
      device       = device,
      geometry     = geometry,
      radius       = radius,
      norm_penalty = norm_penalty
    )$embedding
  }

  fit_replicate <- function(side_a_ids, side_b_ids, replicate_index) {
    emb_a <- fit_one_side(side_a_ids, seed + replicate_index * 2L)
    emb_b <- fit_one_side(side_b_ids, seed + replicate_index * 2L + 1L)
    sdist <- get.rep.dist(list(a = emb_a, b = emb_b))
    1 - sdist[1, 2]
  }

  if (verbose) {
    message("[group_difference_test] Fitting observed (true) group split...")
  }
  observed_correlation <- fit_replicate(
    names(group_vec)[group_vec == group_levels[1]],
    names(group_vec)[group_vec == group_levels[2]],
    replicate_index = 0L
  )

  null_correlations <- vapply(seq_len(n_permutations), function(i) {
    if (verbose) {
      message(sprintf("[group_difference_test] Null permutation %d/%d", i, n_permutations))
    }
    shuffled <- sample(worker_ids)
    side_a <- shuffled[seq_len(n1)]
    side_b <- shuffled[(n1 + 1L):(n1 + n2)]
    fit_replicate(side_a, side_b, replicate_index = i)
  }, numeric(1))

  p_value <- (1 + sum(null_correlations <= observed_correlation)) / (1 + n_permutations)

  structure(
    list(
      observed_correlation = observed_correlation,
      null_correlations = null_correlations,
      p_value = p_value,
      settings = list(
        d = d,
        n_permutations = n_permutations,
        seed = seed,
        group_levels = group_levels,
        group_sizes = c(n1, n2)
      )
    ),
    class = "group_difference_test"
  )
}
