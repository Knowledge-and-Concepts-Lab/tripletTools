#' Exclude participants with suspiciously fast mean reaction times
#'
#' Removes participants whose mean reaction time falls below a threshold,
#' which is used as a heuristic for detecting random or inattentive
#' responding. The comparison is performed on the log scale so that the
#' threshold is applied uniformly regardless of RT distribution skew.
#'
#' @param d Data frame with columns \code{worker_id} and \code{rt}.
#'   \code{rt} will be coerced to numeric via \code{\link[base]{as.numeric}};
#'   non-numeric values become \code{NA} and are excluded from the mean.
#' @param min_mean_rt_ms Numeric. Minimum mean RT in milliseconds. Participants
#'   with \code{mean(rt) < min_mean_rt_ms} are removed. Default: \code{1000}.
#'
#' @return The input data frame with rows belonging to excluded participants
#'   removed.
#'
#' @examples
#' \dontrun{
#' d <- data.frame(
#'   worker_id = c(rep("p1", 100), rep("p2", 100)),
#'   rt        = c(rnorm(100, 1500, 200), rnorm(100, 300, 50))
#' )
#' filter_fast_responders(d, min_mean_rt_ms = 1000)
#' # only p1 is retained
#' }
#'
#' @importFrom magrittr %>%
#' @importFrom dplyr group_by summarise filter pull
#' @importFrom rlang .data
#'
#' @export
filter_fast_responders <- function(d, min_mean_rt_ms = 1000) {
  rts <- d %>%
    group_by(.data$worker_id) %>%
    summarise(
      mean_rt = log(mean(as.numeric(.data$rt), na.rm = TRUE)),
      .groups = "drop"
    )

  slow_enough <- rts %>%
    filter(.data$mean_rt >= log(min_mean_rt_ms)) %>%
    pull("worker_id")

  d %>% filter(.data$worker_id %in% slow_enough)
}
