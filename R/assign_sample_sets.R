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
#' @param df Data frame with columns \code{worker_id} and \code{sampleAlg}.
#'   \code{sampleAlg} must contain the values \code{"check"},
#'   \code{"random"}, and/or \code{"validation"}.
#' @param test_prop Numeric between 0 and 1. Proportion of non-check trials to
#'   assign to the test set. Default: \code{0.2}.
#' @param seed Integer. Random seed passed to \code{\link[base]{set.seed}}
#'   for reproducibility. Default: \code{42}.
#'
#' @return The input data frame with an additional character column
#'   \code{sampleSet} containing \code{"train"}, \code{"test"}, or
#'   \code{NA} (for catch trials).
#'
#' @examples
#' \dontrun{
#' d <- data.frame(
#'   worker_id = rep("p1", 10),
#'   sampleAlg = c(rep("random", 8), rep("check", 2))
#' )
#' assign_sample_sets(d, test_prop = 0.2, seed = 1)
#' }
#'
#' @importFrom magrittr %>%
#' @importFrom dplyr group_by mutate case_when ungroup n
#' @importFrom rlang .data
#'
#' @export
assign_sample_sets <- function(df, test_prop = 0.2, seed = 42) {
  set.seed(seed)
  df %>%
    group_by(.data$worker_id) %>%
    mutate(
      sampleSet = case_when(
        .data$sampleAlg == "check"                             ~ NA_character_,
        .data$sampleAlg == "random" & runif(n()) <= test_prop  ~ "test",
        TRUE                                                   ~ "train"
      )
    ) %>%
    ungroup()
}
