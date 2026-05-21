#' Estimate the latent dimensionality of a triplet dataset
#'
#' Fits embeddings across a range of dimensionalities, each with multiple
#' random restarts, and returns the hold-out loss at every
#' (dimension, restart) combination.  Use the results to select the smallest
#' dimensionality that achieves near-minimum hold-out loss.
#'
#' @section Parallelism:
#' By default the function runs serially.  If the \pkg{future.apply} package
#' is installed, parallelism is controlled by setting a \code{future} plan
#' before calling this function.  Each (d, restart) pair becomes an
#' independent future, so any backend supported by \pkg{future} works:
#' local multicore, SLURM, HTCondor, etc.  See the "Computing Triplet
#' Embeddings" vignette for worked examples.
#'
#' If the \pkg{progressr} package is also installed, a progress bar is shown
#' as jobs complete.  Enable it with \code{progressr::handlers(global = TRUE)}
#' before calling this function, or wrap the call in
#' \code{progressr::with_progress(\{ ... \})}.  Progress reporting works in
#' both serial and parallel modes.
#'
#' @section Method:
#' For each value of \code{d} in \code{dims} and each restart, an independent
#' embedding is trained from a fresh random initialisation (controlled by a
#' deterministic seed derived from \code{seed}, \code{d}, and the restart
#' index).  The best test loss achieved during training is recorded.
#'
#' The \code{summary} element of the return value includes a \code{best_d}
#' column that applies the one-standard-error rule to the per-dimension mean
#' loss: the smallest \code{d} whose mean loss is within one standard error of
#' the global minimum mean loss is flagged as \code{best_d = TRUE}.  This
#' tends to favour parsimony when several dimensions achieve similar loss.
#'
#' @section Item indexing:
#' All unique item names in \code{Center}, \code{Left}, and \code{Right}
#' across all participants are collected and sorted alphabetically; this sorted
#' order defines the zero-based integer indices passed to the Python model.
#'
#' @section Filtering:
#' Trials with \code{NA} in the \code{sampleSet} column (attention-check
#' trials) are excluded before fitting.  The \code{sampleSet} column
#' (\code{"train"} / \code{"test"}) is used to split data for early stopping.
#' If no \code{sampleSet} column is present or all values are \code{NA}, a
#' 70/30 random train/test split is used instead.
#'
#' @param triplet_list A named list of data frames, one per participant, as
#'   returned by \code{\link{get.combined}}.  Each data frame must contain
#'   columns \code{Center}, \code{Left}, \code{Right}, \code{Answer}, and
#'   \code{sampleSet}.
#' @param dims Integer vector of dimensionalities to evaluate.
#'   Default \code{1:8}.
#' @param n_restarts Number of independent random restarts per dimensionality.
#'   Default \code{10L}.  More restarts give a more reliable loss estimate but
#'   multiply compute time.
#' @param max_epochs Maximum training epochs per restart.  Default \code{50000L}.
#' @param tolerance Loss tolerance for early stopping.  Default \code{1e-4}.
#' @param tol_window Epochs without meaningful improvement before early
#'   stopping triggers.  Default \code{10000L}.
#' @param device PyTorch device string, or \code{NULL} (default) to
#'   auto-select: CUDA GPU if available, then Apple MPS, then CPU.
#' @param seed Base integer seed for reproducibility.  Each (d, restart) pair
#'   receives a unique derived seed so all runs are independently replicable.
#'   Default \code{1L}.
#' @param verbose Logical.  If \code{TRUE} (default), print a progress line
#'   before each restart.  Ignored when running in parallel (output from
#'   worker processes is not forwarded to the main session).
#'
#' @return A named list with two elements:
#' \describe{
#'   \item{\code{results}}{Data frame with one row per (dimension, restart) and
#'     columns \code{d}, \code{restart}, \code{loss}, \code{epoch}.}
#'   \item{\code{summary}}{Data frame with one row per dimension and columns
#'     \code{d}, \code{mean_loss}, \code{min_loss}, \code{sd_loss}.
#'     The logical column \code{best_d} marks the smallest \code{d} within
#'     one standard error of the global minimum mean loss.}
#' }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Serial (default)
#' dim_est <- estimate_dimensionality(
#'   triplet_list = icon_triplets,
#'   dims         = 1:6,
#'   n_restarts   = 5L,
#'   max_epochs   = 20000L,
#'   seed         = 42L
#' )
#'
#' # Parallel: use 4 local cores (requires future.apply)
#' library(future)
#' plan(multisession, workers = 4)
#' dim_est <- estimate_dimensionality(icon_triplets, dims = 1:6, n_restarts = 10L)
#' plan(sequential)  # restore serial execution afterwards
#'
#' # Summary with recommended dimensionality flagged
#' dim_est$summary
#'
#' # Plot mean loss +/- 1 SD by dimension
#' s <- dim_est$summary
#' plot(s$d, s$mean_loss, type = "b", pch = 19,
#'      xlab = "Dimensions", ylab = "Mean test loss")
#' arrows(s$d, s$mean_loss - s$sd_loss, s$d, s$mean_loss + s$sd_loss,
#'        angle = 90, code = 3, length = 0.05)
#' abline(v = s$d[s$best_d], lty = 2)
#' }
estimate_dimensionality <- function(triplet_list,
                                    dims        = 1:8,
                                    n_restarts  = 10L,
                                    max_epochs  = 50000L,
                                    tolerance   = 1e-4,
                                    tol_window  = 10000L,
                                    device      = NULL,
                                    seed        = 1L,
                                    verbose     = TRUE) {
  # Collect all item names and sort for consistent zero-based indexing
  all_items <- sort(unique(unlist(lapply(triplet_list, function(df) {
    c(df$Center, df$Left, df$Right)
  }))))

  # Combine all participants, exclude check trials (NA sampleSet), convert indices
  combined <- do.call(rbind, lapply(triplet_list, function(df) {
    df <- df[!is.na(df$sampleSet), ]
    winner <- ifelse(df$Answer == df$Left, df$Left, df$Right)
    loser  <- ifelse(df$Answer == df$Left, df$Right, df$Left)
    data.frame(
      head      = match(df$Center, all_items) - 1L,
      winner    = match(winner,    all_items) - 1L,
      loser     = match(loser,     all_items) - 1L,
      sampleSet = df$sampleSet,
      stringsAsFactors = FALSE
    )
  }))

  train_rows <- combined$sampleSet == "train"
  test_rows  <- combined$sampleSet == "test"

  if (!any(train_rows) || !any(test_rows)) {
    set.seed(seed)
    shuffled  <- combined[sample(nrow(combined)), ]
    split_idx <- floor(0.7 * nrow(shuffled))
    X_train <- as.matrix(shuffled[seq_len(split_idx), c("head", "winner", "loser")])
    X_test  <- as.matrix(shuffled[seq(split_idx + 1L, nrow(shuffled)), c("head", "winner", "loser")])
  } else {
    X_train <- as.matrix(combined[train_rows, c("head", "winner", "loser")])
    X_test  <- as.matrix(combined[test_rows,  c("head", "winner", "loser")])
  }

  # Build a flat list of all (d, restart) jobs
  jobs <- do.call(rbind, lapply(dims, function(d) {
    data.frame(d = d, restart = seq_len(n_restarts),
               random_state = seed + (seq_len(n_restarts) - 1L) * 1000L + d,
               stringsAsFactors = FALSE)
  }))

  fit_one <- function(job) {
    if (verbose) {
      message(sprintf("[estimate_dimensionality] d = %d, restart %d/%d",
                      job$d, job$restart, n_restarts))
    }
    out <- train_embedding(
      X_train      = X_train,
      X_test       = X_test,
      d            = job$d,
      max_epochs   = max_epochs,
      tolerance    = tolerance,
      tol_window   = tol_window,
      device       = device,
      random_state = as.integer(job$random_state),
      print_every  = as.integer(max_epochs)
    )
    data.frame(d = job$d, restart = job$restart,
               loss = out$loss, epoch = out$epoch,
               stringsAsFactors = FALSE)
  }

  job_list <- split(jobs, seq_len(nrow(jobs)))

  use_progressr <- requireNamespace("progressr", quietly = TRUE)
  if (use_progressr) {
    p <- progressr::progressor(steps = nrow(jobs))
    fit_one_prog <- function(job) { out <- fit_one(job); p(); out }
  }

  rows <- if (requireNamespace("future.apply", quietly = TRUE)) {
    future.apply::future_lapply(
      job_list,
      if (use_progressr) fit_one_prog else fit_one,
      future.seed = NULL
    )
  } else {
    lapply(job_list, if (use_progressr) fit_one_prog else fit_one)
  }

  results_df <- do.call(rbind, rows)
  results_df <- results_df[order(results_df$d, results_df$restart), ]
  row.names(results_df) <- NULL

  summary_df <- do.call(rbind, lapply(dims, function(d) {
    sub <- results_df[results_df$d == d, ]
    data.frame(
      d         = d,
      mean_loss = mean(sub$loss),
      min_loss  = min(sub$loss),
      sd_loss   = if (nrow(sub) > 1L) stats::sd(sub$loss) else NA_real_,
      stringsAsFactors = FALSE
    )
  }))

  # 1-SE rule: flag the smallest d within 1 SE of the minimum mean loss
  best_idx  <- which.min(summary_df$mean_loss)
  best_se   <- summary_df$sd_loss[best_idx] / sqrt(n_restarts)
  threshold <- summary_df$mean_loss[best_idx] + best_se
  eligible  <- summary_df$d[summary_df$mean_loss <= threshold]
  summary_df$best_d <- summary_df$d == min(eligible)

  list(results = results_df, summary = summary_df)
}
