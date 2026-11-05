#' Jointly estimate a group-level choice-model shape and refine the group embedding
#'
#' \code{\link{run_group_embedding_from_list}} always fits the group
#' embedding under the crowd-kernel choice model (\eqn{\alpha = 1} on the
#' Student-t continuum used throughout this package's recovery/validation
#' work: \eqn{\alpha = 1} is exactly crowd-kernel \eqn{\mu = 1},
#' \eqn{\alpha \to \infty} is the exact Gaussian limit). This function takes
#' that fit as a starting point and alternates, via coordinate ascent,
#' between (1) re-estimating \eqn{\alpha} by profiled maximum likelihood with
#' the embedding held fixed, and (2) refitting the embedding under the
#' current \eqn{\alpha}, warm-started from the previous iteration -- the
#' group-level analogue of the per-participant joint estimation done by
#' \code{condor_joint_manifold_workflow.py}'s update step
#' (\code{vignette("condor_workflows_vignette")}, Workflow 4), but simpler:
#' there is only one \eqn{\alpha} and one embedding to estimate, so no
#' cross-participant pooling or empirical-Bayes shrinkage is needed.
#'
#' \eqn{\alpha} is re-estimated at each iteration using only
#' \code{sampleAlg == "validation"} trials -- genuinely held out, never used
#' to fit the embedding at any iteration. This is deliberate: profiling
#' \eqn{\alpha} on the same trials the embedding was just optimized against
#' would let the \eqn{\alpha} estimate chase training noise the embedding
#' has already been shaped to fit, rather than measuring real choice-model
#' shape. \code{triplet_list} must therefore contain real validation trials
#' (see \code{\link{set_validation_behavior}}/\code{\link{assign_sample_sets}}
#' to designate some, or \code{\link{find_frequent_triplets}}/
#' \code{\link{assign_validation_from_frequency}} to retrofit a validation
#' set onto legacy data that predates that convention).
#'
#' Iteration stops once the re-estimated \eqn{\alpha} changes by less than
#' \code{tol_log_alpha} (on the log scale) from the previous iteration, or
#' after \code{max_outer} iterations, whichever comes first.
#'
#' @section What this does and does not estimate:
#' Unlike the per-participant joint workflow, there is no population of
#' noisy per-person \eqn{\alpha} estimates to shrink toward each other here
#' -- a single \eqn{\alpha} is estimated from the whole pooled dataset
#' directly, with no regularization pulling it back if it is poorly
#' identified. Check \code{ci} (the final iteration's 95\% profile-likelihood
#' confidence interval) before trusting the point estimate, especially on a
#' small dataset or at large \eqn{\alpha} (the Student-t kernel converges to
#' Gaussian as \eqn{\alpha} grows, so the profile likelihood flattens and
#' \eqn{\alpha} becomes harder to pin down precisely, even though validation
#' accuracy itself is structurally insensitive to \eqn{\alpha} for this
#' choice-model family and so cannot reveal this on its own).
#'
#' @param triplet_list A named list of data frames, one per participant, as
#'   returned by \code{\link{get.combined}} -- the same object passed to
#'   \code{\link{run_group_embedding_from_list}} to produce \code{warm_start}.
#'   Must contain genuine \code{sampleAlg == "validation"} trials (see
#'   Details).
#' @param warm_start Numeric matrix giving the starting embedding: one row
#'   per item (row names = item names) and \code{d} columns, typically the
#'   \code{embedding} returned by a prior call to
#'   \code{\link{run_group_embedding_from_list}} on the same
#'   \code{triplet_list}. Required -- this function refines an
#'   already-fit embedding rather than fitting one from scratch. \code{d} is
#'   taken from \code{ncol(warm_start)}.
#' @param max_epochs,tolerance,tol_window,device,norm_penalty Same meaning as
#'   the matching arguments of \code{\link{run_group_embedding_from_list}},
#'   applied to every embedding-refit step.
#' @param seed Integer random seed, used for the train/test shuffling
#'   fallback (when \code{triplet_list} has no usable \code{sampleSet}
#'   split) and as the embedding fit's \code{random_state} at every outer
#'   iteration.
#' @param max_outer Maximum number of coordinate-ascent iterations. Default
#'   \code{15}.
#' @param tol_log_alpha Convergence threshold on the log scale: stop once
#'   the re-estimated \eqn{\alpha} changes by less than this between
#'   iterations. Default \code{0.05}.
#' @param alpha_grid Candidate \eqn{\alpha} values for the profiled
#'   maximum-likelihood step at each iteration.
#' @param verbose Logical; print one line of progress per outer iteration.
#'   Default \code{TRUE}.
#'
#' @return A named list with five elements:
#' \describe{
#'   \item{\code{embedding}}{Numeric matrix, the final refit embedding (item
#'     names as row names, \code{dim_0}/\code{dim_1}/... columns).}
#'   \item{\code{alpha}}{Final estimated \eqn{\alpha}.}
#'   \item{\code{log_alpha}}{\code{log(alpha)}.}
#'   \item{\code{ci}}{95\% profile-likelihood confidence interval for
#'     \eqn{\alpha} at the final iteration.}
#'   \item{\code{history}}{Data frame with one row per outer iteration:
#'     \code{iter}, \code{alpha}, \code{ll_val} (validation log-likelihood
#'     at the re-estimated \eqn{\alpha}), \code{acc_val} (validation
#'     accuracy), \code{epoch} (embedding-refit stopping epoch), and
#'     \code{delta_log_alpha}.}
#' }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' grp <- run_group_embedding_from_list(icon_triplets, d = 3L)
#' joint <- estimate_group_alpha(icon_triplets, warm_start = grp$embedding)
#' joint$alpha
#' joint$history
#' }
estimate_group_alpha <- function(triplet_list,
                                  warm_start,
                                  max_epochs = 50000L,
                                  tolerance = 1e-4,
                                  tol_window = 10000L,
                                  seed = 222L,
                                  device = NULL,
                                  norm_penalty = 0,
                                  max_outer = 15L,
                                  tol_log_alpha = 0.05,
                                  alpha_grid = 10^seq(log10(2e-4), log10(2e6), length.out = 140),
                                  verbose = TRUE) {

  if (is.null(warm_start) || is.null(rownames(warm_start))) {
    stop("warm_start must be a numeric matrix with row names giving item names -- e.g. the $embedding returned by run_group_embedding_from_list(). Call that first to get an initial alpha = 1 fit.")
  }
  items <- rownames(warm_start)
  d <- ncol(warm_start)
  n_items <- length(items)

  # Same combining convention as run_group_embedding_from_list(): all
  # participants pooled, items indexed 0-based against `items`.
  # sampleSet "train"/"test" trials go into the embedding refit (check
  # trials and holdout-validation trials both have sampleSet == NA and are
  # excluded there automatically); sampleAlg == "validation" trials are
  # used only to profile alpha, regardless of their sampleSet.
  combined <- do.call(rbind, lapply(triplet_list, function(df) {
    winner <- ifelse(df$Answer == df$Left, df$Left, df$Right)
    loser  <- ifelse(df$Answer == df$Left, df$Right, df$Left)
    data.frame(
      head      = match(df$Center, items) - 1L,
      winner    = match(winner,    items) - 1L,
      loser     = match(loser,     items) - 1L,
      sampleSet = df$sampleSet,
      sampleAlg = df$sampleAlg,
      stringsAsFactors = FALSE
    )
  }))

  if (anyNA(combined[c("head", "winner", "loser")])) {
    stop("triplet_list contains items not present in warm_start's row names -- warm_start must cover every item used in triplet_list.")
  }

  val_rows <- combined$sampleAlg == "validation"
  if (!any(val_rows)) {
    stop('No sampleAlg == "validation" trials found in triplet_list. estimate_group_alpha() profiles alpha only on genuinely held-out validation trials, never used to fit the embedding -- see set_validation_behavior()/assign_sample_sets() to designate some, or find_frequent_triplets()/assign_validation_from_frequency() to retrofit one onto legacy data.')
  }
  val_head   <- combined$head[val_rows]
  val_winner <- combined$winner[val_rows]
  val_loser  <- combined$loser[val_rows]

  set.seed(seed)
  train_rows <- !is.na(combined$sampleSet) & combined$sampleSet == "train"
  test_rows  <- !is.na(combined$sampleSet) & combined$sampleSet == "test"
  if (!any(train_rows) || !any(test_rows)) {
    fit_rows  <- !is.na(combined$sampleSet)
    shuffled  <- combined[fit_rows, ][sample(sum(fit_rows)), ]
    split_idx <- floor(0.7 * nrow(shuffled))
    X_train <- as.matrix(shuffled[seq_len(split_idx), c("head", "winner", "loser")])
    X_test  <- as.matrix(shuffled[seq(split_idx + 1L, nrow(shuffled)), c("head", "winner", "loser")])
  } else {
    X_train <- as.matrix(combined[train_rows, c("head", "winner", "loser")])
    X_test  <- as.matrix(combined[test_rows,  c("head", "winner", "loser")])
  }

  compute_py <- .get_compute_py()
  np <- reticulate::import("numpy")
  X_train_np <- np$array(X_train, dtype = np$int32)
  X_test_np  <- np$array(X_test,  dtype = np$int32)

  ## ---- Student-t / crowd-kernel profiled log-likelihood (same formula as
  ## estimate_shrunk_alpha()/ckl_validation_eval() in
  ## R/summarize_joint_estimation.R and inst/condor/condor_joint_manifold_update.R) ----
  softplus <- function(x) ifelse(x > 0, x + log1p(exp(-x)), log1p(exp(x)))
  sum_log_lik <- function(log_s, log_alpha, dw2u, dl2u) {
    s2 <- exp(2 * log_s); alpha <- exp(log_alpha)
    dw2 <- dw2u * s2; dl2 <- dl2u * s2
    log_tw <- -(alpha + 1) / 2 * log1p(dw2 / alpha)
    log_tl <- -(alpha + 1) / 2 * log1p(dl2 / alpha)
    sum(-softplus(log_tl - log_tw))
  }
  profiled_ll <- function(log_alpha, dw2u, dl2u) {
    stats::optimize(function(log_s) sum_log_lik(log_s, log_alpha, dw2u, dl2u),
                     interval = c(-8, 8), maximum = TRUE, tol = 1e-8)$objective
  }

  log_alpha <- 0  # alpha = 1, matching warm_start's own crowd-kernel mu = 1 fit
  embedding <- as.matrix(warm_start[items, , drop = FALSE])
  init_np <- np$array(embedding, dtype = np$float32)

  history <- data.frame(iter = integer(0), alpha = numeric(0), ll_val = numeric(0),
                         acc_val = numeric(0), epoch = integer(0), delta_log_alpha = numeric(0))
  ci <- c(NA_real_, NA_real_)

  for (outer in seq_len(max_outer)) {
    kwargs <- reticulate::dict(module__alpha = exp(log_alpha))
    res <- compute_py$`_fit_offline`(
      X_train_np, X_test_np, n = as.integer(n_items), d = as.integer(d),
      max_epochs = as.integer(max_epochs), tolerance = tolerance,
      tol_window = as.integer(tol_window), print_every = as.integer(max_epochs),
      device = device, noise_model = "TSTE", embedding = init_np,
      random_state = as.integer(seed), module_kwargs = kwargs,
      norm_penalty = norm_penalty
    )
    embedding <- res[[1]]
    rownames(embedding) <- items
    colnames(embedding) <- paste0("dim_", seq_len(d) - 1L)
    epoch <- res[[3]]

    dw2 <- rowSums((embedding[val_head + 1L, ] - embedding[val_winner + 1L, ])^2)
    dl2 <- rowSums((embedding[val_head + 1L, ] - embedding[val_loser  + 1L, ])^2)
    prof <- sapply(alpha_grid, function(a) profiled_ll(log(a), dw2, dl2))
    bi <- which.max(prof)
    new_log_alpha <- log(alpha_grid[bi])
    in_ci <- prof > (prof[bi] - 1.92)  # 95% profile-likelihood CI (chi-sq(1))
    ci <- c(min(alpha_grid[in_ci]), max(alpha_grid[in_ci]))
    acc_val <- mean(dw2 < dl2)  # alpha-invariant for this family; recorded per iteration since the embedding itself changes
    delta <- abs(new_log_alpha - log_alpha)

    history <- rbind(history, data.frame(
      iter = outer, alpha = exp(new_log_alpha), ll_val = prof[bi],
      acc_val = acc_val, epoch = epoch, delta_log_alpha = delta
    ))
    if (verbose) {
      cat(sprintf("[estimate_group_alpha outer %2d] fit at alpha=%.4g -> re-estimated alpha=%.4g (delta_log=%.4f), val ll=%.2f, val acc=%.3f, epoch=%d\n",
                   outer, exp(log_alpha), exp(new_log_alpha), delta, prof[bi], acc_val, epoch))
    }

    log_alpha <- new_log_alpha
    init_np <- np$array(embedding, dtype = np$float32)  # warm-start the next refit

    if (delta < tol_log_alpha) break
  }

  list(embedding = embedding, alpha = exp(log_alpha), log_alpha = log_alpha,
       ci = ci, history = history)
}
