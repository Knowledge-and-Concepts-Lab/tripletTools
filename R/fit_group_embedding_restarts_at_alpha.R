#' Fit a group embedding at a fixed alpha with several random restarts
#'
#' Fits \code{n_restarts} independent, randomly-initialized embeddings at a
#' fixed dimensionality \code{d} and Student-t/crowd-kernel shape
#' \code{alpha}, keeping whichever restart achieves the lowest test loss --
#' the same "several random seeds, keep the best" rule
#' \code{\link{run_group_embedding_from_list}} uses, but at an arbitrary
#' \code{alpha} rather than the crowd-kernel default (\eqn{\alpha = 1}).
#' This is the production "final-final" fit meant to run \emph{after}
#' \code{\link{estimate_group_alpha}} has already determined \code{alpha},
#' as the last step of \code{\link{run_group_embedding_workflow}} -- on data
#' that has had the alpha-profiling sub-pool folded back into training via
#' \code{\link{fold_alpha_test_to_train}}, since that sub-pool's only job
#' (estimating \code{alpha}) is already done by this point.
#'
#' Like \code{\link{estimate_group_alpha}}, this bypasses
#' \code{\link{train_embedding}}'s CKL-only (\eqn{\alpha = 1}) wrapper and
#' calls the underlying \code{_fit_offline()} Python entry point directly
#' (\code{noise_model = "TSTE"}, \code{module_kwargs = list(module__alpha = alpha)}).
#' Restarts are deliberately \strong{not} warm-started from anything -- the
#' point of using several random seeds is to search different local optima,
#' which a shared warm start would mostly defeat.
#'
#' @param triplet_list A list of per-participant data frames, as returned
#'   by \code{\link{get.combined}}, with a usable \code{sampleSet} column
#'   (see \code{\link{prepare_triplet_matrices}}).
#' @param d Embedding dimensionality.
#' @param alpha The fixed Student-t/crowd-kernel shape parameter to fit
#'   under, typically \code{estimate_group_alpha(...)$alpha}.
#' @param n_restarts Number of independent random restarts. Default \code{5L}.
#' @param seed Base integer seed; restart \code{r} uses
#'   \code{seed + (r - 1) * 1000}, the same restart-seed formula used
#'   throughout this package's Condor workflows and
#'   \code{\link{run_group_embedding_workflow}}'s own step 2.
#' @param max_epochs,tolerance,tol_window,device,norm_penalty Same meaning
#'   as the matching arguments of \code{\link{run_group_embedding_from_list}}.
#' @param verbose Logical; print one progress line per restart. Default
#'   \code{TRUE}.
#'
#' @return A named list:
#' \describe{
#'   \item{\code{embedding}}{Numeric matrix, the winning restart's embedding
#'     (item names as row names, \code{dim_0}/\code{dim_1}/... columns).}
#'   \item{\code{loss}}{That restart's test loss.}
#'   \item{\code{epoch}}{Epoch at which that restart's training stopped.}
#'   \item{\code{history}}{That restart's per-epoch training history.}
#'   \item{\code{restart}}{Which restart (1-based) was kept.}
#'   \item{\code{restarts}}{Data frame with one row per restart:
#'     \code{restart}, \code{seed}, \code{loss} -- for inspecting the full
#'     spread, not just the winner.}
#' }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' grp <- run_group_embedding_from_list(icon_triplets, d = 3L)
#' joint <- estimate_group_alpha(icon_triplets, warm_start = grp$embedding)
#' folded <- fold_alpha_test_to_train(icon_triplets, joint$alpha_test_rows)
#' final_final <- fit_group_embedding_restarts_at_alpha(
#'   folded, d = 3L, alpha = joint$alpha, n_restarts = 5L
#' )
#' final_final$embedding
#' }
fit_group_embedding_restarts_at_alpha <- function(triplet_list, d, alpha,
                                                    n_restarts = 5L, seed = 1L,
                                                    max_epochs = 50000L, tolerance = 1e-4,
                                                    tol_window = 10000L, device = NULL,
                                                    norm_penalty = 0, verbose = TRUE) {
  mats <- prepare_triplet_matrices(triplet_list, seed = seed)
  n_items <- length(mats$all_items)

  compute_py <- .get_compute_py()
  np <- reticulate::import("numpy")
  X_train_np <- np$array(mats$X_train, dtype = np$int32)
  X_test_np  <- np$array(mats$X_test,  dtype = np$int32)

  best <- NULL
  best_restart <- NA_integer_
  restarts <- data.frame(restart = integer(0), seed = integer(0), loss = numeric(0))

  for (r in seq_len(n_restarts)) {
    restart_seed <- seed + (r - 1L) * 1000L
    res <- compute_py$`_fit_offline`(
      X_train_np, X_test_np, n = as.integer(n_items), d = as.integer(d),
      max_epochs = as.integer(max_epochs), tolerance = tolerance,
      tol_window = as.integer(tol_window), print_every = as.integer(max_epochs),
      device = device, noise_model = "TSTE", embedding = NULL,
      random_state = as.integer(restart_seed),
      module_kwargs = reticulate::dict(module__alpha = alpha),
      norm_penalty = norm_penalty
    )
    embedding_r <- res[[1]]
    rownames(embedding_r) <- mats$all_items
    colnames(embedding_r) <- paste0("dim_", seq_len(d) - 1L)
    loss_r <- res[[2]]
    epoch_r <- res[[3]]
    history_r <- as.data.frame(res[[5]])

    restarts <- rbind(restarts, data.frame(restart = r, seed = restart_seed, loss = loss_r))

    if (verbose) {
      message(sprintf("  final-final restart %d/%d: seed=%d, test loss=%.6f",
                       r, n_restarts, restart_seed, loss_r))
    }
    if (is.null(best) || loss_r < best$loss) {
      best <- list(embedding = embedding_r, loss = loss_r, epoch = epoch_r, history = history_r)
      best_restart <- r
    }
  }

  if (verbose && n_restarts > 1L) {
    message(sprintf("  keeping final-final restart %d/%d (lowest test loss = %.6f)",
                     best_restart, n_restarts, best$loss))
  }

  list(embedding = best$embedding, loss = best$loss, epoch = best$epoch,
       history = best$history, restart = best_restart, restarts = restarts)
}
