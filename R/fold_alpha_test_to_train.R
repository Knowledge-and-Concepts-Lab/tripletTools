#' Fold the alpha-profiling sub-pool back into training
#'
#' Once \eqn{\alpha} has been estimated by \code{\link{estimate_group_alpha}},
#' the sub-pool of \code{sampleSet == "test"} trials it reserved for
#' profiling \eqn{\alpha} (\code{alpha_test_rows}, part of its return value)
#' has no further job to do -- \eqn{\alpha} is now a fixed number, not
#' something being estimated from anything. Holding that sub-pool out of
#' training any longer is pure waste: there is nothing left for it to stay
#' independent *from*. This function sets \code{sampleSet <- "train"} at
#' exactly those rows (and no others -- in particular, the remaining
#' \code{test_fit} sub-pool is left as \code{"test"}, since it still has a
#' job: governing early stopping for the one last fit at the now-fixed
#' \eqn{\alpha}).
#'
#' @section Why this is a mechanical flip, not a re-derivation:
#' \code{alpha_test_rows} must come from a call to
#' \code{\link{estimate_group_alpha}} on this exact same \code{triplet_list}
#' (same participants, same row order within each). This function does not
#' re-run any random split itself -- it just flips \code{sampleSet} at the
#' positions it's given -- so there is no risk of drifting out of sync with
#' what \eqn{\alpha} was actually profiled on, the way independently
#' re-deriving an equivalent split (e.g. replaying
#' \code{\link{sample_internal_test}} a second time with the same seed)
#' would risk if any upstream detail ever changed.
#'
#' @param triplet_list A named or unnamed list of per-participant data
#'   frames, each with a \code{sampleSet} column -- the same object passed
#'   to \code{\link{estimate_group_alpha}}.
#' @param alpha_test_rows Integer vector, typically
#'   \code{estimate_group_alpha(...)$alpha_test_rows} from a call on this
#'   same \code{triplet_list}: positions (1-based) into
#'   \code{do.call(rbind, triplet_list)} to flip from \code{"test"} to
#'   \code{"train"}.
#'
#' @return \code{triplet_list} with \code{sampleSet} updated at
#'   \code{alpha_test_rows}; a list of the same length, names, and row
#'   order as the input. No other column, and no other row's
#'   \code{sampleSet}, is touched.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' grp <- run_group_embedding_from_list(icon_triplets, d = 3L)
#' joint <- estimate_group_alpha(icon_triplets, warm_start = grp$embedding)
#' folded <- fold_alpha_test_to_train(icon_triplets, joint$alpha_test_rows)
#' # Now fit the real final embedding at (d, joint$alpha) on `folded`,
#' # e.g. with several random-seed restarts, keeping the lowest test loss.
#' }
fold_alpha_test_to_train <- function(triplet_list, alpha_test_rows) {
  if (!is.list(triplet_list) || is.data.frame(triplet_list)) {
    stop("triplet_list must be a list of per-participant triplet data frames.")
  }
  if (length(triplet_list) == 0) {
    stop("'triplet_list' is empty.")
  }
  if (!all(vapply(triplet_list, function(d) "sampleSet" %in% names(d), logical(1)))) {
    stop("Every data frame in 'triplet_list' must have a 'sampleSet' column.")
  }
  if (!is.numeric(alpha_test_rows) || anyNA(alpha_test_rows)) {
    stop("alpha_test_rows must be a non-missing integer/numeric vector.")
  }

  combined <- tag_and_combine_triplet_list(triplet_list)

  if (length(alpha_test_rows) > 0 &&
      (any(alpha_test_rows < 1) || any(alpha_test_rows > nrow(combined)))) {
    stop(sprintf(
      "alpha_test_rows must index rows of do.call(rbind, triplet_list) (1 to %d) -- got values outside that range. Did alpha_test_rows come from estimate_group_alpha() on this same triplet_list?",
      nrow(combined)
    ))
  }

  combined$sampleSet[alpha_test_rows] <- "train"

  split_combined_to_triplet_list(combined, names(triplet_list))
}
