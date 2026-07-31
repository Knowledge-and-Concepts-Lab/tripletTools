#' Estimate the latent dimensionality of a triplet dataset
#'
#' Fits embeddings across a range of dimensionalities, each with multiple
#' random restarts, and returns the hold-out loss at every
#' (dimension, restart) combination.  Use the results to select the smallest
#' dimensionality that achieves near-minimum hold-out loss.
#'
#' @section Group vs. individual mode:
#' When \code{group = TRUE} (the default), all participants' trials are pooled
#' into a single dataset and one dimensionality search is performed over the
#' combined data.  This is appropriate when you want to select a single
#' embedding dimensionality for a group embedding.
#'
#' When \code{group = FALSE}, the search is run independently for each
#' element of \code{triplet_list}, using only that participant's trials.  The
#' return value is then a named list of result objects, one per participant.
#' Item indices are re-built from each participant's own data, so the item
#' space may differ across participants.
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
#' In \code{group = FALSE} mode, indexing is done separately for each
#' participant using only their own trials.
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
#' @param group Logical.  If \code{TRUE} (default), pool all participants'
#'   trials and run a single dimensionality search on the combined data.  If
#'   \code{FALSE}, run the search independently for each participant and return
#'   a named list of result objects.
#' @param geometry Either \code{"euclidean"} (default) or \code{"sphere"}.
#'   When \code{"sphere"}, each restart embeds items onto the surface of a
#'   \code{d}-dimensional sphere of radius \code{radius} (\code{d = 2} is a
#'   circle) instead of freely in \eqn{R^d}.  See the \emph{Spherical
#'   embeddings} section of \code{\link{train_embedding}} for details,
#'   including why this roughly doubles compute time per restart.  Dimensions
#'   in \code{dims} still refer to the ambient dimension of the sphere (its
#'   surface itself has one fewer degree of freedom), so results stay directly
#'   comparable to a \code{geometry = "euclidean"} search over the same
#'   \code{dims}.
#' @param radius Radius of the sphere used when \code{geometry = "sphere"}.
#'   Ignored when \code{geometry = "euclidean"}.  Default \code{1}.
#' @param norm_penalty Non-negative number, forwarded to \code{\link{train_embedding}}'s
#'   \code{norm_penalty} argument for every restart, controlling how each
#'   individual fit chooses its "best" training checkpoint.  Default
#'   \code{0} preserves prior behavior exactly (checkpoints are chosen by
#'   raw test loss).  This changes the actual fitted embeddings and the
#'   \code{loss}/\code{norm_ratio} values reported in \code{results}; it is
#'   independent of \code{best_d_norm_penalty} below, which only affects
#'   \emph{which already-fitted dimension} gets flagged \code{best_d}.  See
#'   the \emph{Diagnosing outlier items} section of
#'   \code{\link{train_embedding}} for details.
#' @param best_d_norm_penalty Non-negative number controlling how much
#'   \code{best_d} selection penalizes dimensions whose fits show outlier
#'   items (see \code{norm_ratio} in the \emph{Diagnosing outlier items}
#'   section of \code{\link{train_embedding}}).  \code{best_d} is chosen by
#'   applying the same one-standard-error rule described below to
#'   \code{penalized_loss = mean_loss + best_d_norm_penalty * (max_norm_ratio - 1)}
#'   instead of \code{mean_loss} directly.  Default \code{NULL} sets it equal
#'   to \code{norm_penalty}, so by default the two stay in sync and
#'   \code{penalized_loss} reflects the same outlier-aversion already
#'   applied during fitting; pass an explicit number (\code{0} to disable,
#'   or any other value) when you want \code{best_d} selection to use a
#'   \emph{different} amount of outlier-aversion than the fits themselves
#'   used.  This is a purely post-hoc selection rule applied to already-
#'   fitted results — \code{results}/\code{summary} always report the raw,
#'   unpenalized \code{loss}/\code{mean_loss} regardless of this setting,
#'   and setting it (unlike \code{norm_penalty}) never changes the fits
#'   themselves.
#'
#' @return When \code{group = TRUE} (the default), a named list with two
#'   elements:
#' \describe{
#'   \item{\code{results}}{Data frame with one row per (dimension, restart) and
#'     columns \code{d}, \code{restart}, \code{loss}, \code{accuracy},
#'     \code{epoch}, \code{norm_ratio}.  \code{loss} and \code{accuracy} are
#'     the hold-out test loss and accuracy at the epoch of best test loss.
#'     \code{norm_ratio} is the ratio of the largest to median per-item
#'     embedding norm at that same epoch — see the \emph{Diagnosing outlier
#'     items} section of \code{\link{train_embedding}}.  \code{norm_ratio}
#'     is only meaningful for \code{geometry = "euclidean"}; always
#'     \code{~1} under \code{geometry = "sphere"}.}
#'   \item{\code{summary}}{Data frame with one row per dimension and columns
#'     \code{d}, \code{mean_loss}, \code{min_loss}, \code{sd_loss},
#'     \code{mean_accuracy}, \code{sd_accuracy}, \code{mean_norm_ratio},
#'     \code{max_norm_ratio}, \code{penalized_loss}.
#'     \code{penalized_loss} equals \code{mean_loss} whenever the
#'     resolved \code{best_d_norm_penalty} (which defaults to
#'     \code{norm_penalty}) is \code{0} — see the \code{best_d_norm_penalty}
#'     argument.  The logical column
#'     \code{best_d} marks the smallest \code{d} within one standard error
#'     of the global minimum \code{penalized_loss}.  A \code{d} with low
#'     \code{mean_loss} but a high \code{max_norm_ratio} relative to
#'     smaller dimensions is a sign that the loss improvement may be coming
#'     from an outlier item being pushed away rather than genuinely better
#'     structure.}
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
#' dim_est <- estimate_dimensionality(
#'   triplet_list = icon_triplets,
#'   dims         = 1:6,
#'   n_restarts   = 5L,
#'   max_epochs   = 20000L,
#'   seed         = 42L
#' )
#' dim_est$summary
#'
#' # Individual mode: separate search per participant
#' dim_est_ind <- estimate_dimensionality(
#'   triplet_list = icon_triplets,
#'   dims         = 1:6,
#'   n_restarts   = 5L,
#'   group        = FALSE
#' )
#' # Best dimensionality for the first participant:
#' dim_est_ind[[1]]$summary
#'
#' # Penalize dimensions whose fits show a strong outlier item when
#' # choosing best_d, rather than selecting on raw mean loss alone
#' # (post-hoc selection only -- does not change the fits themselves)
#' dim_est_penalized <- estimate_dimensionality(
#'   triplet_list      = icon_triplets,
#'   dims              = 1:6,
#'   n_restarts        = 5L,
#'   best_d_norm_penalty = 0.05
#' )
#' dim_est_penalized$summary[, c("d", "mean_loss", "max_norm_ratio",
#'                                "penalized_loss", "best_d")]
#'
#' # Discourage outlier-chasing checkpoints during fitting itself, at every
#' # dimension/restart (changes the fits and reported loss/norm_ratio).
#' # best_d_norm_penalty defaults to norm_penalty, so best_d selection
#' # picks up the same outlier-aversion automatically here.
#' dim_est_fit_penalized <- estimate_dimensionality(
#'   triplet_list = icon_triplets,
#'   dims         = 1:6,
#'   n_restarts   = 5L,
#'   norm_penalty = 0.05
#' )
#'
#' # Same fit-time penalty, but best_d selection back on raw mean_loss
#' dim_est_fit_penalized_unweighted_selection <- estimate_dimensionality(
#'   triplet_list         = icon_triplets,
#'   dims                 = 1:6,
#'   n_restarts           = 5L,
#'   norm_penalty         = 0.05,
#'   best_d_norm_penalty  = 0
#' )
#'
#' # Parallel: use 4 local cores (requires future.apply)
#' library(future)
#' plan(multisession, workers = 4)
#' dim_est <- estimate_dimensionality(icon_triplets, dims = 1:6, n_restarts = 10L)
#' plan(sequential)  # restore serial execution afterwards
#'
#' # Plot mean loss +/- 1 SD by dimension
#' s <- dim_est$summary
#' plot(s$d, s$mean_loss, type = "b", pch = 19,
#'      xlab = "Dimensions", ylab = "Mean test loss")
#' arrows(s$d, s$mean_loss - s$sd_loss, s$d, s$mean_loss + s$sd_loss,
#'        angle = 90, code = 3, length = 0.05)
#' abline(v = s$d[s$best_d], lty = 2)
#'
#' # Compare loss, accuracy, and norm_ratio side by side across dimensions
#' s[, c("d", "mean_loss", "mean_accuracy", "mean_norm_ratio", "max_norm_ratio")]
#' }
estimate_dimensionality <- function(triplet_list,
                                    dims        = 1:8,
                                    n_restarts  = 10L,
                                    max_epochs  = 50000L,
                                    tolerance   = 1e-4,
                                    tol_window  = 10000L,
                                    device      = NULL,
                                    seed        = 1L,
                                    verbose     = TRUE,
                                    group       = TRUE,
                                    geometry    = c("euclidean", "sphere"),
                                    radius      = 1,
                                    norm_penalty = 0,
                                    best_d_norm_penalty = NULL) {
  geometry <- match.arg(geometry)
  if (is.null(best_d_norm_penalty)) best_d_norm_penalty <- norm_penalty

  # Build X_train / X_test matrices from a list of participant data frames
  .prepare_matrices <- function(dfs) {
    all_items <- sort(unique(unlist(lapply(dfs, function(df) {
      c(df$Center, df$Left, df$Right)
    }))))

    combined <- do.call(rbind, lapply(dfs, function(df) {
      df     <- df[!is.na(df$sampleSet), ]
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

    list(X_train = X_train, X_test = X_test)
  }

  # Run the (d, restart) grid search on pre-built matrices
  .run_grid <- function(X_train, X_test) {
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
        print_every  = as.integer(max_epochs),
        geometry     = geometry,
        radius       = radius,
        norm_penalty = norm_penalty
      )
      best <- out$history[which.min(out$history$test_loss), ]
      data.frame(d = job$d, restart = job$restart,
                 loss = out$loss, accuracy = best$test_acc, epoch = out$epoch,
                 norm_ratio = best$norm_ratio,
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

    # best_d_norm_penalty defaults to norm_penalty (resolved above), so
    # penalized_loss == mean_loss unless norm_penalty is also nonzero or
    # the caller passed an explicit, different best_d_norm_penalty.
    summary_df$penalized_loss <- summary_df$mean_loss +
      best_d_norm_penalty * (summary_df$max_norm_ratio - 1)

    best_idx  <- which.min(summary_df$penalized_loss)
    best_se   <- summary_df$sd_loss[best_idx] / sqrt(n_restarts)
    threshold <- summary_df$penalized_loss[best_idx] + best_se
    eligible  <- summary_df$d[summary_df$penalized_loss <= threshold]
    summary_df$best_d <- summary_df$d == min(eligible)

    list(results = results_df, summary = summary_df)
  }

  if (group) {
    mats <- .prepare_matrices(triplet_list)
    .run_grid(mats$X_train, mats$X_test)
  } else {
    result <- lapply(names(triplet_list), function(pid) {
      if (verbose) message(sprintf("[estimate_dimensionality] participant: %s", pid))
      mats <- .prepare_matrices(list(triplet_list[[pid]]))
      .run_grid(mats$X_train, mats$X_test)
    })
    setNames(result, names(triplet_list))
  }
}
