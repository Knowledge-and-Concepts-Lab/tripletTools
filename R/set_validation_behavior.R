#' Set how validation trials are used in an already-split triplet dataset
#'
#' Changes \code{sampleSet} for \code{sampleAlg == "validation"} trials only,
#' leaving every other trial's train/test assignment untouched. Useful when
#' you've already read data in (e.g. via \code{\link{read_raw_data}} or
#' \code{\link{get.combined}}) and want to switch whether validation trials
#' are used to train an embedding, held out as part of the ordinary test
#' set, or excluded entirely as a clean final evaluation set -- without
#' redoing the whole train/test split.
#'
#' @param triplets A single triplet data frame, or a (optionally named) list
#'   of them -- e.g. one element per participant, as returned by
#'   \code{\link{get.combined}}. Each data frame must already have
#'   \code{sampleAlg} and \code{sampleSet} columns (i.e. it has already been
#'   through \code{\link{assign_sample_sets}} or equivalent).
#' @param mode One of \code{"train"}, \code{"test"}, or \code{"holdout"}:
#'   the \code{sampleSet} value to assign to validation trials.
#'   \code{"holdout"} sets it to \code{NA} instead of a string -- the same
#'   treatment as check trials -- excluding validation trials from training
#'   \emph{and} from the test-loss-based model-selection criterion, so they
#'   stay a clean final evaluation set with no double-dipping. Evaluate on
#'   them afterward via \code{\link{get.hoacc}}'s
#'   \code{trialtype = "validation"}, which identifies them through
#'   \code{sampleAlg} rather than \code{sampleSet} for exactly this reason.
#'
#' @return \code{triplets} with \code{sampleSet} updated for validation
#'   trials -- a single data frame if \code{triplets} was one, or a list
#'   (with names preserved) if it was a list. Non-validation trials, and the
#'   \code{sampleAlg} column itself, are returned unchanged.
#'
#' @examples
#' \dontrun{
#' # Single participant
#' d <- set_validation_behavior(icon_triplets[[1]], mode = "test")
#'
#' # A whole list of participants at once
#' triplets_test    <- set_validation_behavior(icon_triplets, mode = "test")
#' triplets_train   <- set_validation_behavior(icon_triplets, mode = "train")
#' triplets_holdout <- set_validation_behavior(icon_triplets, mode = "holdout")
#' }
#'
#' @export
set_validation_behavior <- function(triplets, mode = c("train", "test", "holdout")) {
  mode <- match.arg(mode)
  sample_set_value <- if (mode == "holdout") NA_character_ else mode

  set_one <- function(df) {
    if (!is.data.frame(df)) {
      stop("triplets must be a data frame, or a list of data frames.")
    }
    if (!all(c("sampleAlg", "sampleSet") %in% names(df))) {
      stop("Each triplet data frame must already have sampleAlg and ",
           "sampleSet columns -- run assign_sample_sets() (or equivalent) ",
           "first.")
    }
    is_validation <- !is.na(df$sampleAlg) & df$sampleAlg == "validation"
    df$sampleSet[is_validation] <- sample_set_value
    df
  }

  if (is.data.frame(triplets)) {
    set_one(triplets)
  } else if (is.list(triplets)) {
    lapply(triplets, set_one)
  } else {
    stop("triplets must be a data frame, or a list of data frames.")
  }
}
