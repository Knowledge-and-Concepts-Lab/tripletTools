#' Summarize per-restart dimensionality-search results
#'
#' Aggregates a \code{results} data frame of one row per (dimension,
#' restart) -- the same shape \code{\link{estimate_dimensionality}} returns
#' as its \code{results} element -- into per-dimension summary statistics
#' and a \code{best_d} selection. Exported so results collected from
#' elsewhere (e.g. a Condor-distributed run whose per-restart fits ran via
#' \code{\link{fit_embedding_restart}}) can be aggregated with exactly the
#' same logic \code{estimate_dimensionality()} uses internally.
#'
#' @param results Data frame with one row per (dimension, restart) and at
#'   least columns \code{d}, \code{loss}, \code{accuracy}, \code{norm_ratio}.
#' @param n_restarts Number of restarts per dimension (assumed constant
#'   across dimensions, matching \code{\link{estimate_dimensionality}}'s own
#'   assumption), used for the standard-error term in \code{best_d}
#'   selection.
#' @param best_d_norm_penalty Non-negative number; see
#'   \code{\link{estimate_dimensionality}}'s argument of the same name.
#'   Default \code{0} (post-hoc selection based on raw \code{mean_loss}).
#'
#' @return Data frame with one row per dimension and columns \code{d},
#'   \code{mean_loss}, \code{min_loss}, \code{sd_loss}, \code{mean_accuracy},
#'   \code{sd_accuracy}, \code{mean_norm_ratio}, \code{max_norm_ratio},
#'   \code{penalized_loss}, \code{best_d} -- see
#'   \code{\link{estimate_dimensionality}}'s \code{summary} return element
#'   for what each column means.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # results collected from separately-run restarts, e.g. from Condor jobs
#' summarize_dimensionality(results, n_restarts = 10L)
#' }
summarize_dimensionality <- function(results, n_restarts, best_d_norm_penalty = 0) {
  dims <- sort(unique(results$d))

  summary_df <- do.call(rbind, lapply(dims, function(d) {
    sub <- results[results$d == d, ]
    data.frame(
      d               = d,
      mean_loss       = mean(sub$loss),
      min_loss        = min(sub$loss),
      sd_loss         = if (nrow(sub) > 1L) stats::sd(sub$loss) else NA_real_,
      mean_accuracy   = mean(sub$accuracy),
      sd_accuracy     = if (nrow(sub) > 1L) stats::sd(sub$accuracy) else NA_real_,
      mean_norm_ratio = mean(sub$norm_ratio),
      max_norm_ratio  = max(sub$norm_ratio),
      stringsAsFactors = FALSE
    )
  }))

  # penalized_loss == mean_loss whenever best_d_norm_penalty == 0 (the
  # default), so best_d selection below is unaffected unless a caller
  # opts in.
  summary_df$penalized_loss <- summary_df$mean_loss +
    best_d_norm_penalty * (summary_df$max_norm_ratio - 1)

  best_idx  <- which.min(summary_df$penalized_loss)
  best_se   <- summary_df$sd_loss[best_idx] / sqrt(n_restarts)
  threshold <- summary_df$penalized_loss[best_idx] + best_se
  eligible  <- summary_df$d[summary_df$penalized_loss <= threshold]
  summary_df$best_d <- summary_df$d == min(eligible)

  summary_df
}

#' Summarize per-restart learning-curve results
#'
#' Aggregates a \code{results} data frame of one row per (fraction,
#' restart) -- the same shape \code{\link{estimate_learning_curve}} returns
#' as its \code{results} element -- into per-fraction summary statistics.
#' Exported for the same reason as \code{\link{summarize_dimensionality}}:
#' so externally-collected results can be aggregated identically.
#'
#' @param results Data frame with one row per (fraction, restart) and at
#'   least columns \code{fraction}, \code{n_train}, \code{loss},
#'   \code{accuracy}, \code{norm_ratio}.
#'
#' @return Data frame with one row per fraction and columns \code{fraction},
#'   \code{n_train}, \code{mean_loss}, \code{sd_loss}, \code{mean_accuracy},
#'   \code{sd_accuracy}, \code{mean_norm_ratio}, \code{max_norm_ratio} -- see
#'   \code{\link{estimate_learning_curve}}'s \code{summary} return element
#'   for what each column means.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' summarize_learning_curve(results)
#' }
summarize_learning_curve <- function(results) {
  fractions <- sort(unique(results$fraction))

  do.call(rbind, lapply(fractions, function(f) {
    sub <- results[results$fraction == f, ]
    data.frame(
      fraction         = f,
      n_train          = sub$n_train[1],
      mean_loss        = mean(sub$loss),
      sd_loss          = if (nrow(sub) > 1L) stats::sd(sub$loss) else NA_real_,
      mean_accuracy    = mean(sub$accuracy),
      sd_accuracy      = if (nrow(sub) > 1L) stats::sd(sub$accuracy) else NA_real_,
      mean_norm_ratio  = mean(sub$norm_ratio),
      max_norm_ratio   = max(sub$norm_ratio),
      stringsAsFactors = FALSE
    )
  }))
}
