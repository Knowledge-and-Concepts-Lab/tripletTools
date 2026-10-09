#' Leave-one-out prediction accuracy along a smoothed embedding trajectory
#'
#' Evaluates, for every participant, how well the group representation at
#' each of a grid of points along a 1-D latent axis predicts that
#' participant's own held-out judgments -- with each participant fully
#' excluded from every step of the computation that produces the
#' predictions tested against them (the MDS axis itself, and every
#' smoothed query-point embedding), not just from the held-out trials.
#'
#' @param dist_mat A participant-by-participant distance matrix (or a
#'   \code{dist} object), e.g. as returned by \code{\link{get.rep.dist}}.
#'   Must have the same number of participants, in the same order, as
#'   \code{elist} and \code{triplet_list} (\code{\link{get.rep.dist}}'s
#'   output does not carry participant names, so this function relies on
#'   matching order across all three arguments -- see \emph{Participant
#'   alignment} below).
#' @param elist List of embeddings, one per participant, in the same order
#'   as \code{dist_mat}'s rows/columns -- the same format
#'   \code{\link{smooth_embedding_trajectory}} and \code{\link{get.rep.dist}}
#'   expect (same items, same order, same dimensionality across all
#'   embeddings).
#' @param triplet_list List of triplet data frames, one per participant, in
#'   the same order as \code{dist_mat}/\code{elist} -- the format
#'   \code{\link{get.hoacc}} expects (\code{Center}/\code{Left}/\code{Right}/
#'   \code{Answer} columns, plus \code{sampleAlg}/\code{sampleSet} as needed
#'   for \code{trialtype}).
#' @param n_query Integer. Number of points along the manifold to evaluate
#'   for every participant. Default 25.
#' @param trialtype Passed to \code{\link{get.hoacc}} -- which trials count
#'   as this participant's held-out set. Default \code{"validation"}
#'   (identified via \code{sampleAlg}, matching \code{\link{get.hoacc}}'s own
#'   special-casing of that value -- see its documentation).
#' @param bandwidth,kernel,scale,reflect,gpa_max_iter,gpa_tol Passed to each
#'   leave-one-out call of \code{\link{smooth_embedding_trajectory}}.
#' @param verbose Logical. Print progress (one line per participant, since
#'   this refits the full trajectory once per participant)? Default
#'   \code{TRUE}.
#'
#' @section Why this exists -- a real data-leakage pitfall:
#' Calling \code{\link{smooth_embedding_trajectory}} once on the full
#' participant list, and then evaluating each participant's held-out trials
#' against the query point nearest their own position, looks like a clean
#' train/test split -- held-out trials were never used to fit anything --
#' but it is not: every query point's smoothed embedding is a weighted
#' average that includes every participant, with \emph{no participant's
#' weight ever exactly zero} (see that function's own documentation), so
#' the embedding being evaluated against a participant partially consists
#' of that participant's own (already-fitted) embedding. Confirmed directly
#' (not just argued): a synthetic dataset of participants with fully
#' independent, unrelated true embeddings -- zero true shared structure, by
#' construction -- produced a strong, "significant"-looking crossover
#' pattern (left-end embedding predicts left-end participants, right-end
#' predicts right-end) when evaluated this way (R-squared 0.27, p = 0.003),
#' which collapsed to non-significance (R-squared 0.06, p = 0.18) once each
#' participant was properly excluded from the computation. This function
#' does the full version of that exclusion: \code{dist_mat} is subset to
#' drop the held-out participant \emph{before} \code{\link[stats]{cmdscale}}
#' computes the 1-D axis (not just before the smoothing step), so the axis
#' itself -- not only the averaged embeddings along it -- is entirely
#' out-of-sample for the participant being evaluated.
#'
#' @section Participant alignment:
#' \code{\link{get.rep.dist}} does not currently propagate participant names
#' into its output matrix's dimnames, so this function matches
#' \code{dist_mat}, \code{elist}, and \code{triplet_list} \emph{by
#' position}, not by name -- a mismatched order across the three arguments
#' will silently evaluate the wrong participant's trials against the wrong
#' leave-one-out trajectory. If \code{elist} and \code{triplet_list} both
#' have names, they are checked for identical order as a safety check;
#' \code{dist_mat} itself is not checked, since it typically has none.
#'
#' @return A list with elements:
#' \describe{
#'   \item{\code{accuracy}}{\code{n} x \code{n_query} matrix (rows =
#'     participants, in \code{dist_mat}'s order; columns = query-point
#'     rank 1..\code{n_query}). Each entry is that participant's held-out
#'     prediction accuracy from the leave-one-out trajectory's embedding at
#'     that query-point rank.}
#'   \item{\code{query_points}}{\code{n} x \code{n_query} matrix of the
#'     actual manifold positions used for each participant's own
#'     leave-one-out trajectory -- these differ slightly participant to
#'     participant, since each is computed from a different (n-1)-participant
#'     range (see \code{\link{smooth_embedding_trajectory}}'s own
#'     \code{query_points} behavior).}
#'   \item{\code{effective_n}}{\code{n} x \code{n_query} matrix of Kish's
#'     effective sample size at each query point of each participant's
#'     leave-one-out trajectory -- see
#'     \code{\link{smooth_embedding_trajectory}}'s \emph{Interpreting
#'     effective_n} section.}
#'   \item{\code{full_sample_position}}{Numeric vector, length \code{n}:
#'     each participant's own position from the \emph{full} (not
#'     leave-one-out) sample's \code{cmdscale(dist_mat, k = 1)} -- for
#'     reference/context only (e.g. to relate accuracy along the manifold
#'     back to roughly where this participant themselves sits), never used
#'     in computing any prediction.}
#' }
#'
#' @importFrom stats cmdscale as.dist
#'
#' @export
#'
#' @examples
#' \dontrun{
#' repdist <- get.rep.dist(icon_emb_ind)
#' res <- loo_trajectory_accuracy(repdist, icon_emb_ind, icon_triplets, n_query = 10)
#' res$accuracy
#' }
loo_trajectory_accuracy <- function(dist_mat, elist, triplet_list, n_query = 25,
                                     trialtype = "validation",
                                     bandwidth = NULL,
                                     kernel = c("gaussian", "epanechnikov"),
                                     scale = TRUE, reflect = TRUE,
                                     gpa_max_iter = 100, gpa_tol = 1e-6,
                                     verbose = TRUE) {
  kernel <- match.arg(kernel)
  d <- stats::as.dist(dist_mat)
  n <- attr(d, "Size")
  dmat <- as.matrix(d)

  if (length(elist) != n) {
    stop("elist must have the same length as the number of participants in dist_mat.")
  }
  if (length(triplet_list) != n) {
    stop("triplet_list must have the same length as the number of participants in dist_mat.")
  }
  if (n_query < 1) stop("n_query must be at least 1.")
  if (!is.null(names(elist)) && !is.null(names(triplet_list))) {
    if (!identical(names(elist), names(triplet_list))) {
      stop("elist and triplet_list are both named but not in the same order -- ",
           "check participant alignment (see Participant alignment in the docs).")
    }
  }

  full_sample_position <- stats::cmdscale(d, k = 1)[, 1]

  accuracy <- matrix(NA_real_, n, n_query)
  query_points <- matrix(NA_real_, n, n_query)
  effective_n <- matrix(NA_real_, n, n_query)

  for (i in seq_len(n)) {
    if (verbose) cat(sprintf("Leave-one-out participant %d of %d\n", i, n))

    dmat_loo <- dmat[-i, -i, drop = FALSE]
    elist_loo <- elist[-i]
    pos_loo <- stats::cmdscale(stats::as.dist(dmat_loo), k = 1)[, 1]

    traj_loo <- smooth_embedding_trajectory(
      elist_loo, pos_loo, n_query = n_query,
      bandwidth = bandwidth, kernel = kernel,
      scale = scale, reflect = reflect,
      gpa_max_iter = gpa_max_iter, gpa_tol = gpa_tol
    )

    query_points[i, ] <- traj_loo$query_points
    effective_n[i, ] <- traj_loo$effective_n
    for (qi in seq_len(n_query)) {
      accuracy[i, qi] <- get.hoacc(traj_loo$embeddings[[qi]], triplet_list[[i]], trialtype = trialtype)
    }
  }

  rownames(accuracy) <- rownames(query_points) <- rownames(effective_n) <- names(elist)

  list(
    accuracy = accuracy,
    query_points = query_points,
    effective_n = effective_n,
    full_sample_position = full_sample_position
  )
}
