#' Smoothly averaged embedding trajectory along a 1-D latent axis
#'
#' Given a list of participant embeddings and a corresponding 1-D position
#' for each participant along some latent axis (e.g. the leading
#' classical-MDS dimension of \code{\link{get.rep.dist}}'s output),
#' computes a kernel-weighted average embedding at each of a grid of query
#' points along that axis -- a continuous generalization of splitting
#' participants into discrete bins and averaging each bin's (separately
#' aligned) embedding. That binned approach has two rough edges this
#' avoids: hard bin boundaries discard real position information (two
#' participants who are nearly identical in position but fall either side
#' of a bin edge get treated as fully separate groups), and aligning each
#' bin's mean independently makes bin-to-bin comparisons only loosely
#' comparable, since each bin's own Procrustes fit is free to pick its own
#' rotation. Here, every participant is aligned into one shared frame once
#' (via \code{\link{generalized_procrustes}}), and every query point's
#' average is expressed in that same frame, so the sequence of averaged
#' embeddings is directly comparable across the whole trajectory.
#'
#' @param elist List of embeddings, one per participant, in the same
#'   format \code{\link{generalized_procrustes}} and
#'   \code{\link{get.rep.dist}} expect (same items, same order, same
#'   dimensionality across all embeddings).
#' @param positions Numeric vector, same length and order as \code{elist}:
#'   each participant's position along the latent axis, e.g.
#'   \code{cmdscale(get.rep.dist(elist), k = 1)[, 1]}.
#' @param query_points Numeric vector or \code{NULL}. Positions along the
#'   axis at which to evaluate the averaged embedding. Default \code{NULL}
#'   generates \code{n_query} evenly-spaced points spanning
#'   \code{range(positions)}.
#' @param n_query Integer. Number of query points to generate when
#'   \code{query_points} is \code{NULL}. Default 50.
#' @param bandwidth Numeric or \code{NULL}. Kernel bandwidth controlling how
#'   far along the axis a participant's influence extends. Default
#'   \code{NULL} uses \code{\link[stats]{bw.nrd0}}\code{(positions)}, the
#'   same rule-of-thumb default \code{\link[stats]{density}} uses.
#' @param kernel Character, one of \code{"gaussian"} (default) or
#'   \code{"epanechnikov"}.
#' @param scale,reflect Passed to \code{\link{generalized_procrustes}}.
#' @param gpa_max_iter,gpa_tol Passed to \code{\link{generalized_procrustes}}
#'   as \code{max_iter}/\code{tol}.
#'
#' @section Choosing a bandwidth:
#' This is a smoothing-vs-resolution tradeoff, the same as for any kernel
#' smoother. Too wide a bandwidth washes out real local structure (a
#' genuine reversal or non-monotonic trend along the axis can be averaged
#' away entirely); too narrow leaves each query point's average dominated
#' by whichever one or two participants happen to sit closest to it, which
#' is mostly noise at realistic participant counts. The default
#' (\code{\link[stats]{bw.nrd0}}) is a reasonable starting point, not a
#' guarantee -- compare a couple of bandwidths, and cross-check any
#' interesting local feature (e.g. a reversal near one end) against
#' \code{effective_n} before trusting it (see below).
#'
#' @section Interpreting effective_n:
#' At each query point, participants are weighted by a smooth kernel
#' function of their distance from that point (with the default Gaussian
#' kernel, no participant's weight is ever exactly zero, but distant
#' participants contribute negligibly). \code{effective_n} reports Kish's
#' effective sample size, \eqn{(\sum w_i)^2 / \sum w_i^2}, at each query
#' point -- a standard way to express how many participants are really
#' driving a weighted average, on the original participant-count scale (it
#' equals \code{n} if every participant is weighted equally, and drops
#' toward 1 as the average comes to depend on just one or two
#' participants). Query points near the two ends of \code{positions}'
#' range are the most exposed to this: fewer participants sit nearby, so
#' \code{effective_n} is typically lowest there, and averaged embeddings in
#' that region should be read with that in mind -- an apparent trend near
#' the boundary is more vulnerable to being driven by one or two extreme
#' participants than the same trend in the middle of the range, where many
#' more participants contribute.
#'
#' @return A list with elements:
#' \describe{
#'   \item{\code{query_points}}{As used (supplied or generated).}
#'   \item{\code{embeddings}}{A list the same length as \code{query_points}
#'     (named by each query point's value), each the kernel-weighted
#'     average embedding (in the shared \code{\link{generalized_procrustes}}
#'     frame) at that point.}
#'   \item{\code{effective_n}}{Numeric vector, same length as
#'     \code{query_points} -- see \emph{Interpreting effective_n} above.}
#'   \item{\code{bandwidth}}{As used (supplied or estimated).}
#'   \item{\code{kernel}}{As supplied.}
#'   \item{\code{gpa}}{The full return value of
#'     \code{\link{generalized_procrustes}}, for reference (e.g. to check
#'     \code{gpa$converged}, or to reuse \code{gpa$aligned} directly).}
#' }
#'
#' @importFrom stats bw.nrd0
#'
#' @export
#'
#' @examples
#' \dontrun{
#' repdist <- get.rep.dist(icon_emb_ind)
#' pos <- cmdscale(repdist, k = 1)[, 1]
#' traj <- smooth_embedding_trajectory(icon_emb_ind, pos, n_query = 20)
#' traj$embeddings[[1]]
#' traj$effective_n
#' }
smooth_embedding_trajectory <- function(elist, positions, query_points = NULL,
                                         n_query = 50, bandwidth = NULL,
                                         kernel = c("gaussian", "epanechnikov"),
                                         scale = TRUE, reflect = TRUE,
                                         gpa_max_iter = 100, gpa_tol = 1e-6) {
  kernel <- match.arg(kernel)
  n_embeds <- length(elist)
  if (length(positions) != n_embeds) {
    stop("positions must have the same length as elist.")
  }
  if (any(!is.finite(positions))) stop("positions must be finite, non-missing numbers.")
  if (n_query < 1) stop("n_query must be at least 1.")

  if (is.null(bandwidth)) {
    bandwidth <- stats::bw.nrd0(positions)
  }
  if (bandwidth <= 0) stop("bandwidth must be positive.")

  if (is.null(query_points)) {
    query_points <- seq(min(positions), max(positions), length.out = n_query)
  }

  gpa <- generalized_procrustes(elist, scale = scale, reflect = reflect,
                                 max_iter = gpa_max_iter, tol = gpa_tol)
  aligned <- gpa$aligned

  kernel_fn <- switch(kernel,
    gaussian      = function(u) exp(-0.5 * u^2),
    epanechnikov  = function(u) pmax(0, 1 - u^2)
  )

  template <- aligned[[1]]
  embeddings <- vector("list", length(query_points))
  effective_n <- numeric(length(query_points))

  for (qi in seq_along(query_points)) {
    u <- (positions - query_points[qi]) / bandwidth
    w <- kernel_fn(u)
    total_w <- sum(w)
    if (total_w <= .Machine$double.eps) {
      warning(sprintf(
        paste(
          "No participant has meaningful weight at query point %.4g",
          "(bandwidth too small, or the query point is far outside the",
          "range of positions); returning NA for this point."
        ),
        query_points[qi]
      ))
      embeddings[[qi]] <- matrix(NA_real_, nrow(template), ncol(template),
                                  dimnames = dimnames(template))
      effective_n[qi] <- 0
      next
    }
    w_norm <- w / total_w
    embeddings[[qi]] <- Reduce(`+`, Map(function(mat, wi) mat * wi, aligned, w_norm))
    effective_n[qi] <- total_w^2 / sum(w^2)
  }
  names(embeddings) <- as.character(round(query_points, 4))

  list(
    query_points = query_points,
    embeddings = embeddings,
    effective_n = effective_n,
    bandwidth = bandwidth,
    kernel = kernel,
    gpa = gpa
  )
}
