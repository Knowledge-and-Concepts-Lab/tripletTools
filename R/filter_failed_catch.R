#' Exclude participants who fail too many catch trials
#'
#' Catch trials present the target image as one of the two choices; a correct
#' response requires selecting the choice that matches the target. This
#' function removes any participant whose proportion of incorrect catch-trial
#' responses exceeds \code{max_prop_wrong}.
#'
#' A catch trial is identified by \code{head == winner} (correct response) or
#' \code{head == loser} (incorrect response). Only rows that satisfy one of
#' these conditions contribute to the catch-trial counts; other trial types
#' are ignored.
#'
#' @param d Data frame with columns \code{worker_id}, \code{head},
#'   \code{winner}, and \code{loser}.
#' @param max_prop_wrong Numeric between 0 and 1. Participants with a proportion
#'   of wrong catch-trial responses strictly greater than this value are removed.
#'   Default: \code{0.2}.
#'
#' @return The input data frame with rows belonging to excluded participants
#'   removed.
#'
#' @examples
#' \dontrun{
#' d <- data.frame(
#'   worker_id = rep(c("p1", "p2"), each = 5),
#'   head      = c("cat","cat","dog","dog","cat",  "bird","bird","fish","fish","bird"),
#'   winner    = c("cat","dog","cat","dog","fox",   "bird","crow","fish","tuna","crow"),
#'   loser     = c("dog","cat","dog","cat","bear",  "crow","bird","tuna","fish","bird")
#' )
#' filter_failed_catch(d, max_prop_wrong = 0.4)
#' }
#'
#' @importFrom magrittr %>%
#' @importFrom dplyr group_by summarise filter pull
#' @importFrom rlang .data
#'
#' @export
filter_failed_catch <- function(d, max_prop_wrong = 0.2) {
  catch <- d %>%
    group_by(.data$worker_id) %>%
    summarise(
      prop_wrong = sum(.data$head == .data$loser) /
                   (sum(.data$head == .data$loser) + sum(.data$head == .data$winner)),
      .groups    = "drop"
    )

  bad_ids <- catch %>%
    filter(.data$prop_wrong > max_prop_wrong) %>%
    pull("worker_id")

  d %>% filter(!.data$worker_id %in% bad_ids)
}
