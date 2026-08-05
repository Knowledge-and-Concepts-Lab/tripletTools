#' Estimate a learning curve for a triplet embedding
#'
#' Fits an embedding at a fixed dimensionality using increasing fractions of
#' the training data (10\%, 20\%, ..., 100\% by default), and evaluates
#' every fit against the same fixed hold-out set. Use the results to see how
#' hold-out loss and accuracy improve as more training data is added.
#'
#' @section Group vs. individual mode:
#' When \code{group = TRUE} (the default), all participants' trials are
#' pooled into a single dataset and one learning curve is estimated over the
#' combined data. This is appropriate when you want to know how a
#' group-level embedding's hold-out performance scales with data volume.
#'
#' When \code{group = FALSE}, the learning curve is estimated independently
#' for each element of \code{triplet_list}, using only that participant's
#' trials. The return value is then a named list of result objects, one per
#' participant. Item indices are re-built from each participant's own data,
#' so the item space may differ across participants.
#'
#' @section Sampling scheme:
#' The training pool is shuffled once (controlled by \code{seed}) and then
#' fractions are taken as nested, cumulative prefixes of that shuffled order:
#' the 20\% subset contains every trial in the 10\% subset plus more, and so
#' on up to 100\%. This means differences between fractions reflect only the
#' amount of training data, not which trials happened to be sampled. The
#' hold-out set used for evaluation is the same at every fraction and is
#' never subsampled.
#'
#' @section Parallelism:
#' By default the function runs serially. If the \pkg{future.apply} package
#' is installed, parallelism is controlled by setting a \code{future} plan
#' before calling this function. Each (fraction, restart) pair becomes an
#' independent future, so any backend supported by \pkg{future} works: local
#' multicore, SLURM, HTCondor, etc. In \code{group = FALSE} mode, futures are
#' still resolved at the (fraction, restart) level within each participant's
#' search, run one participant at a time.
#'
#' If the \pkg{progressr} package is also installed, a progress bar is shown
#' as jobs complete. Enable it with \code{progressr::handlers(global = TRUE)}
#' before calling this function, or wrap the call in
#' \code{progressr::with_progress(\{ ... \})}.
#'
#' @section Item indexing:
#' All unique item names in \code{Center}, \code{Left}, and \code{Right}
#' across all participants are collected and sorted alphabetically; this
#' sorted order defines the zero-based integer indices passed to the Python
#' model. In \code{group = FALSE} mode, indexing is done separately for each
#' participant using only their own trials.
#'
#' @section Filtering:
#' Trials with \code{NA} in the \code{sampleSet} column (attention-check
#' trials) are excluded before fitting. The \code{sampleSet} column
#' (\code{"train"} / \code{"test"}) defines the hold-out set. If no
#' \code{sampleSet} column is present or all values are \code{NA}, a 70/30
#' random train/test split is used instead.
#'
#' @param triplet_list A named list of data frames, one per participant, as
#'   returned by \code{\link{get.combined}}. Each data frame must contain
#'   columns \code{Center}, \code{Left}, \code{Right}, \code{Answer}, and
#'   \code{sampleSet}.
#' @param d Number of embedding dimensions to fit at every fraction.
#'   Default \code{5}.
#' @param by Granularity of the training-data fractions, as a proportion of
#'   the full training set. Default \code{0.1}, giving fractions
#'   \code{0.1, 0.2, ..., 1.0}. For example, \code{by = 0.25} gives
#'   \code{0.25, 0.5, 0.75, 1.0}.
#' @param n_restarts Number of independent random restarts per fraction.
#'   Default \code{10L}. More restarts give a more reliable estimate at each
#'   fraction but multiply compute time.
#' @param max_epochs Maximum training epochs per restart. Default \code{50000L}.
#' @param tolerance Loss tolerance for early stopping. Default \code{1e-4}.
#' @param tol_window Epochs without meaningful improvement before early
#'   stopping triggers. Default \code{10000L}.
#' @param device PyTorch device string, or \code{NULL} (default) to
#'   auto-select: CUDA GPU if available, then Apple MPS, then CPU.
#' @param seed Base integer seed for reproducibility. Controls both the
#'   initial shuffle that defines the nested training subsets and the
#'   per-restart initialization seeds. Default \code{1L}.
#' @param verbose Logical. If \code{TRUE} (default), print a progress line
#'   before each restart. Ignored when running in parallel (output from
#'   worker processes is not forwarded to the main session).
#' @param group Logical. If \code{TRUE} (default), pool all participants'
#'   trials and estimate a single learning curve on the combined data. If
#'   \code{FALSE}, estimate the learning curve independently for each
#'   participant and return a named list of result objects.
#' @param norm_penalty Non-negative number, forwarded to
#'   \code{\link{train_embedding}}'s \code{norm_penalty} argument for every
#'   fit, controlling how each fit chooses its "best" training checkpoint.
#'   Default \code{0} preserves prior behavior exactly (checkpoints are
#'   chosen by raw test loss).  See the \emph{Diagnosing outlier items}
#'   section of \code{\link{train_embedding}} for details.
#'
#' @return When \code{group = TRUE} (the default), a named list with two
#'   elements:
#' \describe{
#'   \item{\code{results}}{Data frame with one row per (fraction, restart) and
#'     columns \code{fraction}, \code{n_train}, \code{restart}, \code{loss},
#'     \code{accuracy}, \code{epoch}, \code{norm_ratio}. \code{loss} and
#'     \code{accuracy} are the hold-out test loss and accuracy at the epoch
#'     of best test loss; \code{norm_ratio} is the ratio of the largest to
#'     median per-item embedding norm at that same epoch — see the
#'     \emph{Diagnosing outlier items} section of
#'     \code{\link{train_embedding}}.}
#'   \item{\code{summary}}{Data frame with one row per fraction and columns
#'     \code{fraction}, \code{n_train}, \code{mean_loss}, \code{sd_loss},
#'     \code{mean_accuracy}, \code{sd_accuracy}, \code{mean_norm_ratio},
#'     \code{max_norm_ratio}.  A rising \code{max_norm_ratio} across
#'     fractions alongside improving loss can mean the fit is relying more
#'     on an outlier item as more data comes in, rather than genuinely
#'     stabilizing.}
#' }
#' When \code{group = FALSE}, a named list with one element per participant,
#' each of which has the same \code{results} / \code{summary} structure
#' described above.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Group mode (default): pool all participants
#' curve <- estimate_learning_curve(
#'   triplet_list = icon_triplets,
#'   d            = 3L,
#'   by           = 0.2,
#'   n_restarts   = 5L,
#'   max_epochs   = 20000L,
#'   seed         = 42L
#' )
#' curve$summary
#'
#' # Individual mode: separate learning curve per participant
#' curve_ind <- estimate_learning_curve(
#'   triplet_list = icon_triplets,
#'   d            = 3L,
#'   by           = 0.2,
#'   n_restarts   = 5L,
#'   group        = FALSE
#' )
#' curve_ind[[1]]$summary
#'
#' # Parallel: use 4 local cores (requires future.apply)
#' library(future)
#' plan(multisession, workers = 4)
#' curve <- estimate_learning_curve(icon_triplets, d = 3L, n_restarts = 10L)
#' plan(sequential)  # restore serial execution afterwards
#'
#' # Plot hold-out loss vs. training set size
#' s <- curve$summary
#' plot(s$fraction, s$mean_loss, type = "b", pch = 19,
#'      xlab = "Fraction of training data", ylab = "Mean hold-out loss")
#'
#' # Discourage outlier-chasing checkpoints during fitting itself
#' curve_penalized <- estimate_learning_curve(
#'   triplet_list = icon_triplets,
#'   d            = 3L,
#'   by           = 0.2,
#'   n_restarts   = 5L,
#'   norm_penalty = 0.05
#' )
#' }
estimate_learning_curve <- function(triplet_list,
                                    d          = 5L,
                                    by         = 0.1,
                                    n_restarts = 10L,
                                    max_epochs = 50000L,
                                    tolerance  = 1e-4,
                                    tol_window = 10000L,
                                    device     = NULL,
                                    seed       = 1L,
                                    verbose    = TRUE,
                                    group      = TRUE,
                                    norm_penalty = 0) {

  # Run the fraction/restart grid search on pre-built matrices
  .run_curve <- function(X_train, X_test) {
    # Shuffle the training pool once so that successive fractions are nested,
    # cumulative prefixes rather than independent draws
    set.seed(seed)
    train_df     <- as.data.frame(X_train)[sample(nrow(X_train)), ]
    n_train_pool <- nrow(train_df)

    # Build the fraction grid from the requested granularity
    n_steps   <- ceiling(round(1 / by, 8))
    fractions <- round(seq_len(n_steps) * by, 8)
    fractions[fractions > 1] <- 1
    fractions <- unique(fractions)

    jobs <- do.call(rbind, lapply(seq_along(fractions), function(i) {
      data.frame(frac = fractions[i], restart = seq_len(n_restarts),
                 random_state = seed + (seq_len(n_restarts) - 1L) * 1000L + i,
                 stringsAsFactors = FALSE)
    }))

    fit_one <- function(job) {
      if (verbose) {
        message(sprintf("[estimate_learning_curve] fraction = %.3f, restart %d/%d",
                        job$frac, job$restart, n_restarts))
      }
      n_rows       <- max(1L, round(job$frac * n_train_pool))
      X_train_frac <- as.matrix(train_df[seq_len(n_rows), ])

      row <- fit_embedding_restart(
        X_train      = X_train_frac,
        X_test       = X_test,
        d            = d,
        random_state = job$random_state,
        max_epochs   = max_epochs,
        tolerance    = tolerance,
        tol_window   = tol_window,
        device       = device,
        geometry     = "euclidean",
        radius       = 1,
        norm_penalty = norm_penalty
      )

      data.frame(fraction = job$frac, n_train = n_rows, restart = job$restart,
                 loss = row$loss, accuracy = row$accuracy, epoch = row$epoch_best,
                 norm_ratio = row$norm_ratio,
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
    results_df <- results_df[order(results_df$fraction, results_df$restart), ]
    row.names(results_df) <- NULL

    summary_df <- summarize_learning_curve(results_df)

    list(results = results_df, summary = summary_df)
  }

  if (group) {
    mats <- prepare_triplet_matrices(triplet_list, seed = seed)
    .run_curve(mats$X_train, mats$X_test)
  } else {
    result <- lapply(names(triplet_list), function(pid) {
      if (verbose) message(sprintf("[estimate_learning_curve] participant: %s", pid))
      mats <- prepare_triplet_matrices(list(triplet_list[[pid]]), seed = seed)
      .run_curve(mats$X_train, mats$X_test)
    })
    setNames(result, names(triplet_list))
  }
}
