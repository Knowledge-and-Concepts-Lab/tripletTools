#' Assign trials to train or test sets
#'
#' Randomly assigns each non-catch trial to either a training set or a test
#' set using a stratified split within each participant. Catch trials
#' (\code{sampleAlg == "check"}) receive \code{NA} and are excluded from
#' both sets.
#'
#' The split is performed per participant so that each participant contributes
#' approximately \code{test_prop} of their trials to the test set. Setting
#' \code{seed} ensures the assignment is reproducible.
#'
#' @section Validation trials:
#' \code{sampleAlg == "validation"} trials are a separate category from the
#' \code{"random"} trials that \code{test_prop} splits -- they're routed
#' entirely by \code{train_with_validation} instead: all to \code{"train"}
#' (the default) when they're not being used to evaluate an embedding, or
#' all to \code{"test"} when they are. Re-running this function on the same
#' \code{df} (which must still have \code{sampleAlg}, so this only works
#' before it's dropped from a pipeline's output) with the same \code{seed}
#' but a different \code{train_with_validation} reproduces an identical
#' \code{"random"}-trial split and only changes validation trials, since
#' validation rows never consume any of the random draws \code{test_prop}
#' uses.
#'
#' @param df Data frame with columns \code{worker_id} and \code{sampleAlg}.
#'   \code{sampleAlg} must contain the values \code{"check"},
#'   \code{"random"}, and/or \code{"validation"}.
#' @param test_prop Numeric between 0 and 1. Proportion of non-check,
#'   non-validation trials to assign to the test set. Default: \code{0.2}.
#' @param seed Integer. Random seed passed to \code{\link[base]{set.seed}}
#'   for reproducibility. Default: \code{42}.
#' @param train_with_validation Logical. Whether \code{sampleAlg ==
#'   "validation"} trials are assigned to \code{"train"} (\code{TRUE},
#'   the default) or \code{"test"} (\code{FALSE}) -- set this to
#'   \code{FALSE} when validation trials are instead being held out to
#'   evaluate a fitted embedding. See \emph{Validation trials} below.
#'
#' @return The input data frame with an additional character column
#'   \code{sampleSet} containing \code{"train"}, \code{"test"}, or
#'   \code{NA} (for catch trials).
#'
#' @examples
#' \dontrun{
#' d <- data.frame(
#'   worker_id = rep("p1", 10),
#'   sampleAlg = c(rep("random", 6), rep("check", 2), rep("validation", 2))
#' )
#' assign_sample_sets(d, test_prop = 0.2, seed = 1)
#' # Hold validation trials out for evaluation instead:
#' assign_sample_sets(d, test_prop = 0.2, seed = 1, train_with_validation = FALSE)
#' }
#'
#' @importFrom magrittr %>%
#' @importFrom dplyr group_by mutate case_when ungroup n
#' @importFrom rlang .data
#'
#' @export
assign_sample_sets <- function(df, test_prop = 0.2, seed = 42,
                                train_with_validation = TRUE) {
  set.seed(seed)
  df %>%
    group_by(.data$worker_id) %>%
    mutate(
      sampleSet = case_when(
        .data$sampleAlg == "check"                                  ~ NA_character_,
        .data$sampleAlg == "random" & runif(n()) <= test_prop       ~ "test",
        .data$sampleAlg == "validation" & !train_with_validation    ~ "test",
        TRUE                                                        ~ "train"
      )
    ) %>%
    ungroup()
}
