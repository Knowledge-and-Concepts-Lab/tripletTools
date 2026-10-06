#' Assign trials to train or test sets
#'
#' Randomly assigns each non-catch trial to either a training set or a test
#' set using a stratified split within each participant. Catch trials
#' (\code{sampleAlg == "check"}) receive \code{NA} and are excluded from
#' both sets.
#'
#' The split is performed per participant: within each participant's
#' \code{sampleAlg == "random"} trials, exactly
#' \code{round(test_prop * n_random)} of them (chosen uniformly at random,
#' without replacement) are assigned to the test set, and the rest to
#' train. Using an exact count rather than an independent per-trial
#' coin-flip means two participants with the same number of random trials
#' always get the same number (and proportion) of test trials -- not just
#' approximately, as an i.i.d. Bernoulli draw per trial would give -- and
#' participants with different trial counts still get matched
#' \emph{proportions}, with the exact per-participant count controlled by
#' rounding. Setting \code{seed} ensures the assignment is reproducible.
#'
#' @section Validation trials:
#' \code{sampleAlg == "validation"} trials are a separate category from the
#' \code{"random"} trials that \code{test_prop} splits -- they're routed
#' entirely by \code{validation_mode} instead: all to \code{"train"} (the
#' default) when they're not being used to evaluate an embedding, all to
#' \code{"test"} when they are, or all to \code{NA} (excluded from both --
#' same treatment as check trials) when you want them held out as a clean
#' final evaluation set that never influences training \emph{or} the
#' early-stopping/model-selection criterion, avoiding the double-dipping
#' that comes from putting them in the ordinary test set a model is also
#' selected against. Use \code{\link{get.hoacc}}'s
#' \code{trialtype = "validation"} to evaluate on them afterward (it
#' identifies them via \code{sampleAlg}, not \code{sampleSet}, since
#' \code{sampleSet} no longer labels them as anything once they're
#' excluded this way). Re-running this function on the same \code{df}
#' (which must still have \code{sampleAlg}, so this only works before it's
#' dropped from a pipeline's output) with the same \code{seed} but a
#' different \code{validation_mode} reproduces an identical
#' \code{"random"}-trial split and only changes validation trials, since
#' validation rows never consume any of the random draws \code{test_prop}
#' uses. \code{\link{set_validation_behavior}} offers the same three modes
#' for data that's already been through this function, without redoing
#' the \code{"random"}-trial split.
#'
#' @param df Data frame with columns \code{worker_id} and \code{sampleAlg}.
#'   \code{sampleAlg} must contain the values \code{"check"},
#'   \code{"random"}, and/or \code{"validation"}.
#' @param test_prop Numeric between 0 and 1. Proportion of non-check,
#'   non-validation trials to assign to the test set. Default: \code{0.2}.
#' @param seed Integer. Random seed passed to \code{\link[base]{set.seed}}
#'   for reproducibility. Default: \code{42}.
#' @param validation_mode One of \code{"train"} (the default),
#'   \code{"test"}, or \code{"holdout"} -- where \code{sampleAlg ==
#'   "validation"} trials are routed. See \emph{Validation trials} below.
#'
#' @return The input data frame with an additional character column
#'   \code{sampleSet} containing \code{"train"}, \code{"test"}, or
#'   \code{NA} (for catch trials, and for validation trials when
#'   \code{validation_mode = "holdout"}).
#'
#' @examples
#' \dontrun{
#' d <- data.frame(
#'   worker_id = rep("p1", 10),
#'   sampleAlg = c(rep("random", 6), rep("check", 2), rep("validation", 2))
#' )
#' assign_sample_sets(d, test_prop = 0.2, seed = 1)
#' # Hold validation trials out for evaluation instead:
#' assign_sample_sets(d, test_prop = 0.2, seed = 1, validation_mode = "test")
#' # Exclude them from training and model selection entirely, for use as a
#' # clean final evaluation set via get.hoacc(trialtype = "validation"):
#' assign_sample_sets(d, test_prop = 0.2, seed = 1, validation_mode = "holdout")
#' }
#'
#' @importFrom magrittr %>%
#' @importFrom dplyr group_by mutate case_when ungroup n
#' @importFrom rlang .data
#'
#' @export
assign_sample_sets <- function(df, test_prop = 0.2, seed = 42,
                                validation_mode = c("train", "test", "holdout")) {
  validation_mode <- match.arg(validation_mode)
  set.seed(seed)
  df %>%
    group_by(.data$worker_id) %>%
    mutate(
      sampleSet = {
        is_test_random <- select_test_trials(.data$sampleAlg, test_prop)
        case_when(
          .data$sampleAlg == "check"                                        ~ NA_character_,
          .data$sampleAlg == "random" & is_test_random                      ~ "test",
          .data$sampleAlg == "validation" & validation_mode == "holdout"    ~ NA_character_,
          .data$sampleAlg == "validation" & validation_mode == "test"       ~ "test",
          TRUE                                                              ~ "train"
        )
      }
    ) %>%
    ungroup()
}

# Picks exactly round(test_prop * n_random) of the sampleAlg == "random"
# entries (uniformly at random, without replacement) to be test trials --
# an exact count per participant rather than an independent per-trial
# Bernoulli draw, so participants with the same number of random trials get
# the same number of test trials, not just the same expected number.
select_test_trials <- function(sample_alg, test_prop) {
  is_random <- sample_alg == "random"
  n_random  <- sum(is_random)
  n_test    <- round(test_prop * n_random)

  out <- rep(FALSE, length(sample_alg))
  out[is_random][sample.int(n_random, n_test)] <- TRUE
  out
}
