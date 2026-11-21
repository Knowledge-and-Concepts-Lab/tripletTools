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
#' Iteration stops once the re-estimated \eqn{\alpha} changes by less than
#' \code{tol_log_alpha} (on the log scale) from the previous iteration, or
#' after \code{max_outer} iterations, whichever comes first.
#'
#' @section Where alpha is profiled from, and why not sampleAlg == "validation":
#' \eqn{\alpha} must be re-estimated at each iteration on trials that never
#' influenced the embedding -- profiling it on the same trials the embedding
#' was just shaped to fit (directly, via the gradient step, or indirectly,
#' via early-stopping checkpoint selection) would let the \eqn{\alpha}
#' estimate chase sample-specific noise rather than measuring real
#' choice-model shape. An earlier version of this function used
#' \code{sampleAlg == "validation"} trials for this, since those are this
#' package's existing convention for a trial pool nothing else ever touches.
#' That has a real cost on datasets where validation trials are the whole
#' point of calling this function in the first place: it leaves nothing
#' genuinely untouched afterward to report the finished (embedding,
#' \eqn{\alpha}) pair's quality against, since the one trial pool designed
#' for that (\code{\link{get.hoacc}}'s \code{trialtype = "validation"}) has
#' itself just been used as a tuning input.
#'
#' The actual requirement for a clean \eqn{\alpha}-profiling pool is
#' disjointness from whatever selected the embedding -- it does not have to
#' be literally labeled \code{sampleAlg == "validation"}. This function
#' instead splits the \code{sampleSet == "test"} pool itself (via
#' \code{\link{sample_internal_test}}, the same mechanism
#' \code{\link{estimate_dimensionality}} uses to carve \code{internal_test}
#' out of \code{sampleSet == "train"}) into two disjoint parts, fixed once
#' for the whole coordinate-ascent run: \code{alpha_test_frac} of it is set
#' aside purely to profile \eqn{\alpha} (step 1), and the rest continues to
#' do early stopping/checkpoint selection for the embedding refit (step 2),
#' exactly the role the full \code{test} pool would otherwise play. Neither
#' sub-pool ever touches \code{train}. Any real \code{sampleAlg ==
#' "validation"} trials in \code{triplet_list} are therefore left completely
#' untouched by this function -- free to serve afterward as an honest,
#' never-used final-quality check on the finished model.
#'
#' The cost is the mirror image of the problem this solves: splitting
#' \code{test} further means less data for checkpoint selection, which gets
#' somewhat noisier. On a dataset with abundant randomly-sampled trials (the
#' usual case for the legacy data this is meant to help with) that's a far
#' better place to absorb the cost than shrinking an already-scarce
#' validation pool.
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
#' \eqn{\alpha} becomes harder to pin down precisely, even though
#' alpha-test accuracy itself is structurally insensitive to \eqn{\alpha}
#' for this choice-model family and so cannot reveal this on its own).
#'
#' @param triplet_list A named list of data frames, one per participant, as
#'   returned by \code{\link{get.combined}} -- the same object passed to
#'   \code{\link{run_group_embedding_from_list}} to produce \code{warm_start}.
#'   Must contain a usable \code{sampleSet} column (see Details); no longer
#'   requires \code{sampleAlg == "validation"} trials (see the section above).
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
#'   split), for the \code{alpha_test_frac} split of the \code{test} pool
#'   (see above), and as the embedding fit's \code{random_state} at every
#'   outer iteration.
#' @param alpha_test_frac Proportion of the \code{sampleSet == "test"} pool
#'   set aside to profile \eqn{\alpha}, drawn once (not re-split per outer
#'   iteration) via \code{\link{sample_internal_test}}. The remaining
#'   \code{1 - alpha_test_frac} continues to do early stopping for the
#'   embedding refit. Must satisfy \code{0 < alpha_test_frac < 1}. Default
#'   \code{0.5}.
#' @param max_outer Maximum number of coordinate-ascent iterations. Default
#'   \code{15}.
#' @param tol_log_alpha Convergence threshold on the log scale: stop once
#'   the re-estimated \eqn{\alpha} changes by less than this between
#'   iterations. Default \code{0.05}.
#' @param alpha_grid Candidate \eqn{\alpha} values for the profiled
#'   maximum-likelihood step at each iteration.
#' @param verbose Logical; print the alpha-test/checkpoint-selection split
#'   sizes once up front, then one line of progress per outer iteration.
#'   Default \code{TRUE}.
#'
#' @return A named list with seven elements:
#' \describe{
#'   \item{\code{embedding}}{Numeric matrix, the final refit embedding (item
#'     names as row names, \code{dim_0}/\code{dim_1}/... columns).}
#'   \item{\code{alpha}}{Final estimated \eqn{\alpha}.}
#'   \item{\code{log_alpha}}{\code{log(alpha)}.}
#'   \item{\code{ci}}{95\% profile-likelihood confidence interval for
#'     \eqn{\alpha} at the final iteration.}
#'   \item{\code{history}}{Data frame with one row per outer iteration:
#'     \code{iter}, \code{alpha}, \code{ll_alpha_test} (log-likelihood on the
#'     alpha-test pool at the re-estimated \eqn{\alpha}), \code{acc_alpha_test}
#'     (accuracy on that same pool), \code{epoch} (embedding-refit stopping
#'     epoch), and \code{delta_log_alpha}.}
#'   \item{\code{n_test_fit}}{Row count of the sub-pool used for the embedding
#'     refit's own early stopping.}
#'   \item{\code{n_alpha_test}}{Row count of the sub-pool used to profile
#'     \eqn{\alpha}.}
#'   \item{\code{alpha_test_rows}}{Integer vector of length
#'     \code{n_alpha_test}: the positions (1-based, into
#'     \code{do.call(rbind, triplet_list)}) of the rows used to profile
#'     \eqn{\alpha}. Pass this directly to
#'     \code{\link{fold_alpha_test_to_train}} (on the same
#'     \code{triplet_list}) once \eqn{\alpha} is finalized, to fold this
#'     sub-pool back into training for one last fit at the now-fixed
#'     \eqn{\alpha} -- its only job (estimating \eqn{\alpha}) is done at
#'     that point, so there is nothing left for holding it out to protect.}
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
#'
#' # Any real sampleAlg == "validation" trials in icon_triplets are left
#' # untouched by the call above -- safe to use afterward for an honest
#' # final check, e.g.:
#' # get.hoacc(joint$embedding, icon_triplets[[1]], trialtype = "validation")
#' }
estimate_group_alpha <- function(triplet_list,
                                  warm_start,
                                  max_epochs = 50000L,
                                  tolerance = 1e-4,
                                  tol_window = 10000L,
                                  seed = 222L,
                                  device = NULL,
                                  norm_penalty = 0,
                                  alpha_test_frac = 0.5,
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
  # participants pooled, items indexed 0-based against `items`. Only
  # sampleSet is needed now -- sampleAlg == "validation" trials are no
  # longer read or used by this function (see the roxygen section above).
  combined <- do.call(rbind, lapply(triplet_list, function(df) {
    winner <- ifelse(df$Answer == df$Left, df$Left, df$Right)
    loser  <- ifelse(df$Answer == df$Left, df$Right, df$Left)
    data.frame(
      head      = match(df$Center, items) - 1L,
      winner    = match(winner,    items) - 1L,
      loser     = match(loser,     items) - 1L,
      sampleSet = df$sampleSet,
      stringsAsFactors = FALSE
    )
  }))

  if (anyNA(combined[c("head", "winner", "loser")])) {
    stop("triplet_list contains items not present in warm_start's row names -- warm_start must cover every item used in triplet_list.")
  }

  # .row_pos tracks each row's position in do.call(rbind, triplet_list) --
  # needed because combined's own row names can't be trusted for this:
  # rbind.data.frame() disambiguates colliding names from different
  # triplet_list elements (every element's own data.frame() call starts
  # row-naming at "1") with .1/.2 suffixes, so rownames(combined) is not a
  # reliable 1:n position index. Threading an explicit column through every
  # subset instead is what lets alpha_test_rows (below) report real
  # triplet_list positions for fold_alpha_test_to_train() to use later.
  combined$.row_pos <- seq_len(nrow(combined))

  set.seed(seed)
  train_rows <- !is.na(combined$sampleSet) & combined$sampleSet == "train"
  test_rows  <- !is.na(combined$sampleSet) & combined$sampleSet == "test"
  if (!any(train_rows) || !any(test_rows)) {
    fit_rows  <- !is.na(combined$sampleSet)
    shuffled  <- combined[fit_rows, ][sample(sum(fit_rows)), ]
    split_idx <- floor(0.7 * nrow(shuffled))
    train_df <- shuffled[seq_len(split_idx), ]
    test_df  <- shuffled[seq(split_idx + 1L, nrow(shuffled)), ]
  } else {
    train_df <- combined[train_rows, ]
    test_df  <- combined[test_rows,  ]
  }
  X_train <- as.matrix(train_df[, c("head", "winner", "loser")])
  X_test  <- as.matrix(data.frame(head = test_df$head, winner = test_df$winner,
                                   loser = test_df$loser, row_pos = test_df$.row_pos))

  # Split the held-out test pool itself into two disjoint sub-pools, fixed
  # once for the whole coordinate-ascent run (not re-drawn per outer
  # iteration): X_test_fit continues to do early stopping/checkpoint
  # selection for the embedding refit (step 2), exactly the role the full
  # X_test would otherwise play; X_alpha_test is reserved only for
  # profiling alpha (step 1). Neither ever touches X_train, and
  # X_alpha_test additionally never touches X_test_fit -- see the "Where
  # alpha is profiled from" section above. The extra row_pos column rides
  # along through the same shuffle/split (sample_internal_test() doesn't
  # care how many columns X_train has), so alpha_test_rows below is read
  # off afterward rather than computed by a second, separate random draw.
  split             <- sample_internal_test(X_test, frac = alpha_test_frac, seed = seed)
  X_test_fit        <- split$X_fit[, c("head", "winner", "loser"), drop = FALSE]
  X_alpha_test      <- split$X_internal_test[, c("head", "winner", "loser"), drop = FALSE]
  alpha_test_rows   <- split$X_internal_test[, "row_pos"]
  atest_head   <- X_alpha_test[, "head"]
  atest_winner <- X_alpha_test[, "winner"]
  atest_loser  <- X_alpha_test[, "loser"]

  if (verbose) {
    cat(sprintf("[estimate_group_alpha] test pool split: %d row(s) for embedding-refit early stopping, %d row(s) reserved for alpha profiling (alpha_test_frac = %s)\n",
                 nrow(X_test_fit), nrow(X_alpha_test), format(alpha_test_frac)))
  }

  compute_py <- .get_compute_py()
  np <- reticulate::import("numpy")
  X_train_np <- np$array(X_train, dtype = np$int32)
  X_test_np  <- np$array(X_test_fit, dtype = np$int32)

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

  history <- data.frame(iter = integer(0), alpha = numeric(0), ll_alpha_test = numeric(0),
                         acc_alpha_test = numeric(0), epoch = integer(0), delta_log_alpha = numeric(0))
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

    # drop = FALSE: at d = 1, embedding[rows, ] would otherwise degenerate to
    # a plain vector (R's default single-column-matrix-subsetting behavior),
    # breaking rowSums() below -- a real, latent bug exposed by exercising
    # this function at d = 1 for the first time.
    dw2 <- rowSums((embedding[atest_head + 1L, , drop = FALSE] - embedding[atest_winner + 1L, , drop = FALSE])^2)
    dl2 <- rowSums((embedding[atest_head + 1L, , drop = FALSE] - embedding[atest_loser  + 1L, , drop = FALSE])^2)
    prof <- sapply(alpha_grid, function(a) profiled_ll(log(a), dw2, dl2))
    bi <- which.max(prof)
    new_log_alpha <- log(alpha_grid[bi])
    in_ci <- prof > (prof[bi] - 1.92)  # 95% profile-likelihood CI (chi-sq(1))
    ci <- c(min(alpha_grid[in_ci]), max(alpha_grid[in_ci]))
    acc_alpha_test <- mean(dw2 < dl2)  # alpha-invariant for this family; recorded per iteration since the embedding itself changes
    delta <- abs(new_log_alpha - log_alpha)

    history <- rbind(history, data.frame(
      iter = outer, alpha = exp(new_log_alpha), ll_alpha_test = prof[bi],
      acc_alpha_test = acc_alpha_test, epoch = epoch, delta_log_alpha = delta
    ))
    if (verbose) {
      cat(sprintf("[estimate_group_alpha outer %2d] fit at alpha=%.4g -> re-estimated alpha=%.4g (delta_log=%.4f), alpha-test ll=%.2f, alpha-test acc=%.3f, epoch=%d\n",
                   outer, exp(log_alpha), exp(new_log_alpha), delta, prof[bi], acc_alpha_test, epoch))
    }

    log_alpha <- new_log_alpha
    init_np <- np$array(embedding, dtype = np$float32)  # warm-start the next refit

    if (delta < tol_log_alpha) break
  }

  list(embedding = embedding, alpha = exp(log_alpha), log_alpha = log_alpha,
       ci = ci, history = history,
       n_test_fit = nrow(X_test_fit), n_alpha_test = nrow(X_alpha_test),
       alpha_test_rows = alpha_test_rows)
}
