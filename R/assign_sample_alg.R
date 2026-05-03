#' Label each trial with its sampling algorithm
#'
#' Adds a \code{sampleAlg} column to a trial-level data frame based on the
#' structure of each row. This is used with legacy data that does not include
#' a \code{trial_category} column exported directly from jsPsych. For data
#' collected with the current experiment template, \code{trial_category} is
#' available directly and can be renamed to \code{sampleAlg} instead.
#'
#' Classification rules (applied in order):
#' \enumerate{
#'   \item If \code{head == winner} or \code{head == loser}, the trial is a
#'         catch (attention check) trial: \code{"check"}.
#'   \item If \code{validation == TRUE}, the trial is a validation trial:
#'         \code{"validation"}.
#'   \item Otherwise: \code{"random"}.
#' }
#'
#' @param d Data frame with columns \code{head}, \code{winner}, \code{loser},
#'   and \code{validation}.
#'
#' @return The input data frame with an additional character column
#'   \code{sampleAlg} containing \code{"check"}, \code{"validation"}, or
#'   \code{"random"}.
#'
#' @examples
#' \dontrun{
#' d <- data.frame(
#'   head       = c("cat", "dog", "bird"),
#'   winner     = c("cat", "fish", "eagle"),
#'   loser      = c("dog", "frog", "sparrow"),
#'   validation = c(FALSE, FALSE, TRUE)
#' )
#' assign_sample_alg(d)
#' }
#'
#' @importFrom magrittr %>%
#' @importFrom dplyr mutate case_when
#' @importFrom rlang .data
#'
#' @export
assign_sample_alg <- function(d) {
  d %>%
    mutate(
      sampleAlg = case_when(
        .data$head == .data$winner | .data$head == .data$loser ~ "check",
        .data$validation == TRUE                               ~ "validation",
        TRUE                                                   ~ "random"
      )
    )
}
