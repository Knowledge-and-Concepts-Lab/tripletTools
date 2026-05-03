#' Exclude participants with too few trials
#'
#' Removes participants who completed fewer than \code{min_trials} experiment
#' trials, as well as any rows with a missing \code{worker_id}. This guards
#' against partially-completed sessions being included in downstream analyses.
#'
#' @param d Data frame with a \code{worker_id} column.
#' @param min_trials Integer. Minimum number of trials required for a
#'   participant to be retained. Default: \code{510}.
#'
#' @return The input data frame with rows belonging to excluded participants
#'   (and rows with \code{NA} worker IDs) removed.
#'
#' @examples
#' \dontrun{
#' d <- data.frame(
#'   worker_id = c(rep("p1", 600), rep("p2", 100)),
#'   rt        = rnorm(700, 1500, 300)
#' )
#' filter_incomplete(d, min_trials = 510)
#' # only p1 is retained
#' }
#'
#' @importFrom magrittr %>%
#' @importFrom dplyr group_by summarise filter pull n
#' @importFrom rlang .data
#'
#' @export
filter_incomplete <- function(d, min_trials = 510) {
  trial_counts <- d %>%
    group_by(.data$worker_id) %>%
    summarise(total_trials = n(), .groups = "drop")

  invalid <- trial_counts %>%
    filter(.data$total_trials < min_trials | is.na(.data$worker_id)) %>%
    pull("worker_id")

  d %>% filter(!.data$worker_id %in% invalid)
}
