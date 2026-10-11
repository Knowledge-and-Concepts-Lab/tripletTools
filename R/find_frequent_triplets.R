#' Find the most frequently repeated triplets across participants
#'
#' Given a list of per-participant triplet data frames, finds the triplets
#' judged by the largest number of distinct participants, treating a triplet
#' as the same trial regardless of which option appeared on the left or the
#' right (but not regardless of which item was the reference/\code{Center}
#' item -- that's a different question being asked, not the same trial
#' mirrored).
#'
#' @param triplet_list Named list of per-participant triplet data frames (the
#'   package's standard \code{Center}/\code{Left}/\code{Right}/\code{Answer}/
#'   \code{worker_id} shape, e.g. \code{icon_triplets}).
#' @param n Integer. Number of triplets to return, ranked by the number of
#'   distinct participants who judged them (ties broken by total trial
#'   count, then alphabetically by the triplet's own name -- see Details).
#'   Default 50.
#' @param min_participants Integer. Only triplets judged by at least this
#'   many distinct participants are eligible to be returned, even if fewer
#'   than \code{n} such triplets exist. Default 1 (no filtering).
#' @param exclude_check Logical. Drop \code{sampleAlg == "check"} rows
#'   (attention-check trials) before counting, if a \code{sampleAlg} column
#'   is present. Default \code{TRUE}.
#'
#' @returns A data frame with one row per selected triplet, sorted by
#'   decreasing frequency, with columns:
#'   \describe{
#'     \item{triplet}{The triplet's unique code, from
#'       \code{\link{make.tripnames}} (\code{Center_Left_Right}, with
#'       \code{Left}/\code{Right} in a fixed, left/right-independent order).}
#'     \item{Center, Left, Right}{The triplet's items, in the format
#'       \code{\link{test.model}}/\code{\link{get.hoacc}} expect -- so the
#'       result can be used directly as (or merged into) a
#'       \code{Center}/\code{Left}/\code{Right}/\code{Answer}-shaped triplet
#'       data frame once an \code{Answer} is assigned (e.g. a majority vote,
#'       the same way \code{\link{make.vmat}} computes one for genuine
#'       validation trials).}
#'     \item{n_participants}{Number of distinct participants (by
#'       \code{worker_id}) who judged this triplet at least once.}
#'     \item{n_trials}{Total number of trials judging this triplet, pooled
#'       across all participants -- can exceed \code{n_participants} if any
#'       one participant judged the same triplet more than once.}
#'   }
#'
#' @details
#' This is for retrofitting a post-hoc validation set onto legacy data
#' collected before this package's \code{sampleAlg == "validation"}
#' convention existed, where every triplet was instead sampled independently
#' at random for each participant. Because triplets are drawn from a
#' combinatorially large pool (an \code{m}-item study has
#' \code{m * choose(m - 1, 2)} distinct \code{Center}/\{\code{Left},
#' \code{Right}\} combinations), real cross-participant overlap is only
#' likely to turn up when \code{m} is small and/or the number of trials per
#' participant is large relative to that pool -- check that
#' \code{n_participants} actually reaches a usable minimum for the top
#' triplets returned here before treating them as a real validation set,
#' rather than assuming it from the item count alone.
#'
#' Once a usable set of frequent triplets is found, a natural next step is
#' to compute each one's majority-vote answer across the participants who
#' judged it (the same construction \code{\link{make.vmat}} uses for genuine
#' validation trials) and treat that as its \code{Answer} for a held-out
#' evaluation set. This function only finds and counts the candidate
#' triplets -- it does not compute majority votes itself, since doing so
#' meaningfully requires first deciding on a frequency/participant threshold
#' using the counts returned here.
#'
#' Triplet identity is determined by \code{\link{make.tripnames}}, the same
#' convention \code{\link{make.vmat}} uses for genuine validation trials:
#' two trials are the same triplet if they share the same \code{Center} and
#' the same unordered pair of \code{Left}/\code{Right} items. A trial with
#' the same three items but a different \code{Center} is a different
#' question (a different reference item), not the same triplet mirrored,
#' and is counted separately.
#'
#' @importFrom stringr str_sort
#'
#' @export
#'
#' @examples
#' freq <- find_frequent_triplets(icon_triplets, n = 10)
#' freq
find_frequent_triplets <- function(triplet_list, n = 50, min_participants = 1,
                                    exclude_check = TRUE) {

  if (!is.list(triplet_list) || is.data.frame(triplet_list)) {
    stop("triplet_list must be a list of per-participant triplet data frames.")
  }
  if (n < 1) stop("n must be at least 1.")
  if (min_participants < 1) stop("min_participants must be at least 1.")

  combined <- do.call(rbind, triplet_list)

  if (is.null(combined$worker_id)) {
    stop("Every data frame in triplet_list must have a 'worker_id' column.")
  }

  if (exclude_check && !is.null(combined$sampleAlg)) {
    combined <- combined[is.na(combined$sampleAlg) | combined$sampleAlg != "check", ]
  }

  combined$tripname <- make.tripnames(combined)
  combined <- combined[!is.na(combined$tripname), ]

  trips <- unique(combined$tripname)

  n_participants <- tapply(combined$worker_id, combined$tripname, function(x) length(unique(x)))
  n_trials <- tapply(combined$worker_id, combined$tripname, length)
  n_participants <- as.integer(n_participants[trips])
  n_trials <- as.integer(n_trials[trips])

  # Representative Center/Left/Right for each triplet, from the first trial
  # that produced it -- same pattern make.vmat() uses, for the same reason:
  # parsing Center/Left/Right back out of the joined tripname string is
  # ambiguous when item names themselves contain underscores.
  first_idx <- match(trips, combined$tripname)
  left_vals  <- combined$Left[first_idx]
  right_vals <- combined$Right[first_idx]
  ordered <- mapply(function(a, b) str_sort(c(a, b), numeric = TRUE),
                     left_vals, right_vals)

  out <- data.frame(
    triplet = trips,
    Center = combined$Center[first_idx],
    Left = ordered[1, ],
    Right = ordered[2, ],
    n_participants = n_participants,
    n_trials = n_trials,
    stringsAsFactors = FALSE
  )

  out <- out[out$n_participants >= min_participants, , drop = FALSE]

  # Sort descending by n_participants, then n_trials, then alphabetically by
  # triplet name, so the ordering is fully deterministic even when ties
  # remain on both frequency columns.
  ord <- order(-out$n_participants, -out$n_trials, out$triplet)
  out <- out[ord, , drop = FALSE]

  out <- utils::head(out, n)
  rownames(out) <- NULL
  out
}
