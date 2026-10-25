## Internal helpers for summarize_joint_estimation() -------------------

read_joint_manifold_run <- function(output_dir) {
  manifest_path <- file.path(output_dir, "run_manifest.txt")
  if (!file.exists(manifest_path)) {
    stop("No run_manifest.txt found in ", output_dir,
         " -- is this a condor_joint_manifold_workflow.py output directory?")
  }
  manifest_lines <- readLines(manifest_path)
  manifest <- list()
  for (ln in manifest_lines) {
    if (!grepl(":", ln, fixed = TRUE)) next
    kv <- strsplit(ln, ":", fixed = TRUE)[[1]]
    manifest[[trimws(kv[1])]] <- trimws(paste(kv[-1], collapse = ":"))
  }

  worker_ids_path <- file.path(output_dir, "setup", "worker_ids.txt")
  item_order_path <- file.path(output_dir, "setup", "item_order.txt")
  if (!file.exists(worker_ids_path) || !file.exists(item_order_path)) {
    stop("setup/worker_ids.txt and setup/item_order.txt are required (written by a ",
         "condor_joint_manifold_workflow.py run with resume support) but were not found in ",
         output_dir, ".")
  }
  worker_ids <- scan(worker_ids_path, what = character(), quiet = TRUE)
  item_order <- scan(item_order_path, what = character(), quiet = TRUE)

  n_outer <- suppressWarnings(as.integer(manifest[["n_outer"]]))
  if (is.na(n_outer)) {
    iter_dirs <- list.files(output_dir, pattern = "^iter[0-9]+$")
    n_outer <- if (length(iter_dirs)) max(as.integer(sub("^iter", "", iter_dirs))) else 0L
  }
  d <- suppressWarnings(as.integer(manifest[["d"]]))

  n <- length(worker_ids)
  positions_mat <- matrix(NA_real_, n, n_outer, dimnames = list(worker_ids, NULL))
  alpha_mat <- matrix(NA_real_, n, n_outer, dimnames = list(worker_ids, NULL))
  alpha_diag_traj <- data.frame(iter = seq_len(n_outer), tau2 = NA_real_,
                                 pop_mean_alpha = NA_real_, bandwidth = NA_real_)
  for (i in seq_len(n_outer)) {
    pos_path <- file.path(output_dir, paste0("iter", i), "positions.csv")
    alpha_path <- file.path(output_dir, paste0("iter", i), "alpha.csv")
    if (file.exists(pos_path)) {
      positions_mat[, i] <- utils::read.csv(pos_path, stringsAsFactors = FALSE)$position
    }
    if (file.exists(alpha_path)) {
      a <- utils::read.csv(alpha_path, stringsAsFactors = FALSE)
      alpha_mat[, i] <- a$alpha
      alpha_diag_traj$tau2[i] <- a$tau2[1]
      alpha_diag_traj$pop_mean_alpha[i] <- a$pop_mean_alpha[1]
      alpha_diag_traj$bandwidth[i] <- a$bandwidth[1]
    }
  }

  read_person_dir_embeddings <- function(dir_path) {
    if (!dir.exists(dir_path)) return(NULL)
    out <- lapply(seq_along(worker_ids), function(i) {
      p <- file.path(dir_path, sprintf("person%d.csv", i - 1))
      if (!file.exists(p)) return(NULL)
      raw <- utils::read.csv(p, stringsAsFactors = FALSE)
      rownames(raw) <- raw$item
      as.matrix(raw[item_order, setdiff(names(raw), "item"), drop = FALSE])
    })
    if (any(vapply(out, is.null, logical(1)))) return(NULL)
    names(out) <- worker_ids
    out
  }
  original_embeddings <- read_person_dir_embeddings(file.path(output_dir, "setup", "original_embeddings"))

  read_long_embeddings <- function(path) {
    if (!file.exists(path)) return(NULL)
    raw <- utils::read.csv(path, stringsAsFactors = FALSE)
    raw$worker_id <- as.character(raw$worker_id)
    out <- lapply(worker_ids, function(w) {
      sub <- raw[raw$worker_id == w, ]
      if (!nrow(sub)) return(NULL)
      rownames(sub) <- sub$item
      as.matrix(sub[item_order, setdiff(names(sub), c("worker_id", "item")), drop = FALSE])
    })
    if (any(vapply(out, is.null, logical(1)))) return(NULL)
    names(out) <- worker_ids
    out
  }
  final_embeddings <- read_long_embeddings(file.path(output_dir, "final_embeddings.csv"))
  final_smoothed_embeddings <- read_long_embeddings(file.path(output_dir, "final_smoothed_embeddings.csv"))

  final_positions <- NULL
  fp_path <- file.path(output_dir, "final_positions.csv")
  if (file.exists(fp_path)) {
    fp <- utils::read.csv(fp_path, stringsAsFactors = FALSE)
    fp$worker_id <- as.character(fp$worker_id)
    final_positions <- stats::setNames(fp$position, fp$worker_id)[worker_ids]
  }

  final_alpha <- NULL
  fa_path <- file.path(output_dir, "final_alpha.csv")
  if (file.exists(fa_path)) {
    fa <- utils::read.csv(fa_path, stringsAsFactors = FALSE)
    fa$worker_id <- as.character(fa$worker_id)
    final_alpha <- stats::setNames(fa$alpha, fa$worker_id)[worker_ids]
  }

  final_grand_mean_embedding <- NULL
  gm_path <- file.path(output_dir, "final_grand_mean_embedding.csv")
  if (file.exists(gm_path)) {
    gm <- utils::read.csv(gm_path, stringsAsFactors = FALSE)
    rownames(gm) <- gm$item
    final_grand_mean_embedding <- as.matrix(gm[item_order, setdiff(names(gm), "item"), drop = FALSE])
  }

  if (is.na(d)) {
    ref <- final_embeddings %||% original_embeddings
    d <- if (!is.null(ref)) ncol(ref[[1]]) else NA_integer_
  }

  list(
    output_dir = output_dir, manifest = manifest, n_outer = n_outer, d = d,
    worker_ids = worker_ids, item_order = item_order,
    positions_mat = positions_mat, alpha_mat = alpha_mat, alpha_diag_traj = alpha_diag_traj,
    original_embeddings = original_embeddings, final_embeddings = final_embeddings,
    final_positions = final_positions,
    final_smoothed_embeddings = final_smoothed_embeddings, final_alpha = final_alpha,
    final_grand_mean_embedding = final_grand_mean_embedding
  )
}

`%||%` <- function(a, b) if (is.null(a)) b else a

flag_unstable_joint_positions <- function(positions_mat, window = 5, threshold_frac = 0.1) {
  n_outer <- ncol(positions_mat)
  w <- min(window, n_outer)
  recent <- positions_mat[, (n_outer - w + 1):n_outer, drop = FALSE]
  recent_range <- apply(recent, 1, function(x) diff(range(x, na.rm = TRUE)))
  last_change <- if (n_outer >= 2) {
    abs(positions_mat[, n_outer] - positions_mat[, n_outer - 1])
  } else {
    rep(NA_real_, nrow(positions_mat))
  }
  full_range <- diff(range(positions_mat[, n_outer], na.rm = TRUE))
  flagged <- if (full_range > 0) recent_range > threshold_frac * full_range else rep(FALSE, nrow(positions_mat))
  data.frame(
    worker_id = rownames(positions_mat),
    final_position = positions_mat[, n_outer],
    recent_range = recent_range,
    last_change = last_change,
    flagged = flagged,
    row.names = NULL
  )
}

## Same convergence check as flag_unstable_joint_positions(), applied to
## each participant's own alpha trajectory instead of position. Operates in
## log-alpha space (alpha's natural, roughly log-normal scale -- matching
## every other alpha computation in this file and in
## condor_joint_manifold_update.R) so that "recent range" is comparable
## across participants regardless of their alpha's absolute magnitude.
flag_unstable_joint_alpha <- function(alpha_mat, window = 5, threshold_frac = 0.1) {
  log_alpha_mat <- log(alpha_mat)
  n_outer <- ncol(log_alpha_mat)
  w <- min(window, n_outer)
  recent <- log_alpha_mat[, (n_outer - w + 1):n_outer, drop = FALSE]
  recent_range <- apply(recent, 1, function(x) diff(range(x, na.rm = TRUE)))
  last_change <- if (n_outer >= 2) {
    abs(log_alpha_mat[, n_outer] - log_alpha_mat[, n_outer - 1])
  } else {
    rep(NA_real_, nrow(log_alpha_mat))
  }
  full_range <- diff(range(log_alpha_mat[, n_outer], na.rm = TRUE))
  flagged <- if (full_range > 0) recent_range > threshold_frac * full_range else rep(FALSE, nrow(log_alpha_mat))
  data.frame(
    worker_id = rownames(alpha_mat),
    final_alpha = alpha_mat[, n_outer],
    recent_log_range = recent_range,
    last_log_change = last_change,
    flagged = flagged,
    row.names = NULL
  )
}

## Per-person profiled MLE of alpha (bounded grid -- avoids the
## unconstrained-optimizer runaway confirmed for participants whose own
## data is highly self-consistent) with empirical-Bayes shrinkage toward a
## precision-weighted population mean (standard random-effects
## DerSimonian-Laird estimator of the between-person variance net of
## estimation noise). Same procedure condor_joint_manifold_update.R uses
## each iteration; kept here too as the fallback when a run's own
## final_alpha.csv isn't available (e.g. an older run from before alpha was
## decoupled from position), so the held-out comparison below always has a
## properly-regularized alpha to evaluate rather than silently falling back
## to something cruder.
estimate_shrunk_alpha <- function(embeddings, fit_trials) {
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
  dist_fn <- function(X, trials) {
    list(dw2 = rowSums((X[trials$head, , drop = FALSE] - X[trials$winner, , drop = FALSE])^2),
         dl2 = rowSums((X[trials$head, , drop = FALSE] - X[trials$loser, , drop = FALSE])^2))
  }
  workers <- names(embeddings)
  n <- length(workers)
  alpha_grid <- 10^seq(log10(2e-4), log10(2e6), length.out = 140)
  log_alpha_hat <- stats::setNames(numeric(n), workers)
  se_log_alpha <- stats::setNames(numeric(n), workers)
  for (w in workers) {
    d_w <- dist_fn(embeddings[[w]], fit_trials[[w]])
    prof <- sapply(alpha_grid, function(a) profiled_ll(log(a), d_w$dw2, d_w$dl2))
    bi <- which.max(prof)
    log_alpha_hat[w] <- log(alpha_grid[bi])
    in_ci <- prof > (prof[bi] - 1.92)
    lo <- min(log(alpha_grid[in_ci])); hi <- max(log(alpha_grid[in_ci]))
    se_log_alpha[w] <- (hi - lo) / (2 * 1.96)
  }
  w_i <- 1 / se_log_alpha^2
  pop_mean_log_alpha <- sum(w_i * log_alpha_hat) / sum(w_i)
  Q <- sum(w_i * (log_alpha_hat - pop_mean_log_alpha)^2)
  tau2 <- max(0, (Q - (n - 1)) / (sum(w_i) - sum(w_i^2) / sum(w_i)))
  w_shrink <- tau2 / (tau2 + se_log_alpha^2)
  log_alpha_shrunk <- pop_mean_log_alpha + w_shrink * (log_alpha_hat - pop_mean_log_alpha)
  exp(log_alpha_shrunk)
}

## Profiled Student-t/crowd-kernel choice-model log-likelihood and accuracy
## on held-out trials, for a set of per-participant embeddings and
## per-participant log-alpha values. Same formulas used throughout the
## joint-manifold Condor workflow (condor_joint_manifold_update.R,
## condor_joint_manifold_fit.R) and its validation analyses -- kept here as
## a proper internal helper rather than duplicated again, since (unlike the
## Condor scripts, which are deliberately self-contained for cluster
## deployment) this lives inside the package itself.
ckl_validation_eval <- function(embeddings, log_alphas, fit_trials, val_trials) {
  softplus <- function(x) ifelse(x > 0, x + log1p(exp(-x)), log1p(exp(x)))
  sum_log_lik <- function(log_s, log_alpha, dw2u, dl2u) {
    s2 <- exp(2 * log_s); alpha <- exp(log_alpha)
    dw2 <- dw2u * s2; dl2 <- dl2u * s2
    log_tw <- -(alpha + 1) / 2 * log1p(dw2 / alpha)
    log_tl <- -(alpha + 1) / 2 * log1p(dl2 / alpha)
    sum(-softplus(log_tl - log_tw))
  }
  profiled_ll <- function(log_alpha, dw2u, dl2u) {
    opt <- stats::optimize(function(log_s) sum_log_lik(log_s, log_alpha, dw2u, dl2u),
                            interval = c(-8, 8), maximum = TRUE, tol = 1e-8)
    list(ll = opt$objective, log_s = opt$maximum)
  }
  dist_fn <- function(X, trials) {
    list(dw2 = rowSums((X[trials$head, , drop = FALSE] - X[trials$winner, , drop = FALSE])^2),
         dl2 = rowSums((X[trials$head, , drop = FALSE] - X[trials$loser, , drop = FALSE])^2))
  }
  workers <- names(embeddings)
  ll <- numeric(length(workers)); acc <- numeric(length(workers))
  names(ll) <- names(acc) <- workers
  for (w in workers) {
    if (!length(fit_trials[[w]]$head) || !length(val_trials[[w]]$head)) {
      ll[w] <- NA_real_; acc[w] <- NA_real_
      next
    }
    d_fit <- dist_fn(embeddings[[w]], fit_trials[[w]])
    fit <- profiled_ll(log_alphas[[w]], d_fit$dw2, d_fit$dl2)
    d_val <- dist_fn(embeddings[[w]], val_trials[[w]])
    ll[w] <- sum_log_lik(fit$log_s, log_alphas[[w]], d_val$dw2, d_val$dl2)
    acc[w] <- mean(d_val$dw2 < d_val$dl2)
  }
  list(ll = ll, acc = acc)
}

build_jm_trial_lists <- function(triplet_data, worker_ids, fit_sample_alg = "random",
                                  val_trialtype = "validation") {
  if (is.null(triplet_data$worker_id)) stop("triplet_data must have a worker_id column.")
  if (is.null(triplet_data$sampleAlg)) stop("triplet_data must have a sampleAlg column.")
  td <- triplet_data
  td_worker_chr <- as.character(td$worker_id)
  make_trials <- function(sub) {
    list(head = sub$Center, winner = sub$Answer,
         loser = ifelse(sub$Left == sub$Answer, sub$Right, sub$Left))
  }
  fit_trials <- lapply(worker_ids, function(w) {
    make_trials(td[td_worker_chr == w & !is.na(td$sampleAlg) & td$sampleAlg == fit_sample_alg, ])
  })
  names(fit_trials) <- worker_ids
  val_trials <- lapply(worker_ids, function(w) {
    if (identical(val_trialtype, "validation")) {
      sub <- td[td_worker_chr == w & !is.na(td$sampleAlg) & td$sampleAlg == "validation", ]
    } else {
      if (is.null(td$sampleSet)) stop("triplet_data must have a sampleSet column for val_trialtype != \"validation\".")
      sub <- td[td_worker_chr == w & !is.na(td$sampleSet) & td$sampleSet == val_trialtype, ]
    }
    make_trials(sub)
  })
  names(val_trials) <- worker_ids
  list(fit_trials = fit_trials, val_trials = val_trials)
}

compare_jm_conditions <- function(test, ref) {
  tt  <- stats::t.test(test$ll,  ref$ll,  paired = TRUE)
  tta <- tryCatch(stats::t.test(test$acc, ref$acc, paired = TRUE), error = function(e) NULL)
  data.frame(
    n_win_ll     = sum(test$ll  > ref$ll,  na.rm = TRUE),
    mean_diff_ll = round(mean(test$ll - ref$ll, na.rm = TRUE), 3),
    t_ll         = round(unname(tt$statistic), 3),
    p_ll         = signif(tt$p.value, 3),
    n_win_acc    = sum(test$acc > ref$acc, na.rm = TRUE),
    p_acc        = if (is.null(tta)) NA_real_ else signif(tta$p.value, 3)
  )
}

md_table <- function(df) {
  hdr <- paste0("| ", paste(names(df), collapse = " | "), " |")
  sep <- paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|")
  rows <- apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))
  c(hdr, sep, rows)
}

#' Summarize a joint-manifold Condor workflow run
#'
#' Reads the output directory of \code{condor_joint_manifold_workflow.py}
#' (package \code{inst/condor/}) and produces a self-contained Markdown
#' report covering the diagnostics this project has repeatedly needed by
#' hand for each new dataset run through that workflow: whether the
#' per-participant position \emph{and} alpha estimates actually converged
#' (estimated independently of each other -- geometry position and
#' choice-model shape are not tied to a single shared curve; see
#' \code{condor_joint_manifold_update.R}'s own documentation for why), and
#' -- when the original triplet data is supplied -- whether the
#' kernel-smoothed production estimate beats each participant's own
#' individual embedding on held-out validation trials, with the
#' embedding-pooling and alpha-shrinkage contributions to that advantage
#' reported separately (not just their combined effect, which conflates
#' the two -- see \emph{Why the decomposition, not just one comparison}
#' below).
#'
#' @param output_dir Path to a \code{condor_joint_manifold_workflow.py}
#'   output directory (must contain \code{run_manifest.txt},
#'   \code{setup/worker_ids.txt}, and \code{setup/item_order.txt} --
#'   written by that workflow's resume-support code).
#' @param triplet_data \code{NULL} (default), or a combined triplet data
#'   frame in this package's standard format (\code{Center}/\code{Left}/
#'   \code{Right}/\code{Answer}/\code{sampleAlg}/\code{worker_id} columns --
#'   the same shape \code{\link{get.combined}} produces, or one element of
#'   \code{icon_triplets}/\code{color_triplets} row-bound together). When
#'   supplied, this is the \emph{original} raw triplet data (including
#'   validation trials), not anything already inside \code{output_dir} --
#'   validation trials are deliberately never passed to the Condor workflow
#'   itself (see \code{assign_sample_sets()}'s \code{"holdout"} mode), so
#'   there is no way to recover them from \code{output_dir} alone. If
#'   \code{NULL}, the held-out comparison and leave-one-out check are
#'   skipped and the report says so.
#' @param run_loo_check Logical. When \code{triplet_data} is supplied, also
#'   run \code{\link{loo_trajectory_accuracy}} (fully out-of-sample, no
#'   alpha component, not expensive -- refits a simple kernel-smoothed
#'   trajectory once per participant using each participant's
#'   \emph{original} embedding, not the full joint alternating procedure).
#'   Default \code{TRUE}.
#' @param fit_sample_alg,val_trialtype Which \code{sampleAlg}/trial type
#'   counts as fitting vs. held-out data, passed to the internal trial-list
#'   builder and to \code{\link{loo_trajectory_accuracy}}'s
#'   \code{trialtype}. Defaults \code{"random"} and \code{"validation"},
#'   matching this project's standard convention.
#' @param oscillation_window,oscillation_threshold A participant is flagged
#'   as possibly not converged if their position's range (or, separately,
#'   their log-alpha's range -- position and alpha are estimated
#'   independently now, so each gets its own convergence check) over the
#'   last \code{oscillation_window} outer iterations exceeds
#'   \code{oscillation_threshold} times the full sample's final-iteration
#'   range on that same scale. Defaults 5 and 0.1 -- tuned against a real
#'   non-convergent position case (oscillation amplitude ~0.35 against a
#'   full range of ~1.4, comfortably above this threshold) and several
#'   genuinely converged boundary cases (recent-iteration range under
#'   0.01). Not a universal constant; adjust if a dataset's own position or
#'   alpha scale makes the default too strict or too lax.
#' @param item_colors Character vector, same length and order as
#'   \code{setup/item_order.txt}, or \code{NULL} (default): colors for the
#'   embedding-geometry grid. With no dataset-specific semantics available
#'   in general, the default colors items by their position in
#'   \code{item_order.txt} via \code{\link[grDevices]{rainbow}}; pass a
#'   semantically meaningful vector (e.g. an \code{hsv()} scheme keyed to
#'   known item properties) for a more informative plot.
#' @param n_geometry_panels Integer, number of evenly-spaced query points
#'   across the recovered position range to show in the embedding-geometry
#'   grid. Default 6. Only plotted when \code{d} (read from
#'   \code{run_manifest.txt}) is 2 or 3; skipped (with a note in the report)
#'   otherwise.
#' @param output_md Path to write the Markdown report to. Default
#'   \code{file.path(output_dir, "summary.md")}. Figures are written as PNG
#'   files to a sibling \verb{<name>_files/} directory and referenced with
#'   relative paths, so the report is self-contained if copied as a unit.
#' @param verbose Logical, print progress. Default \code{TRUE}.
#'
#' @section Why the decomposition, not just one comparison:
#' The production comparison (pooled estimate vs. each participant's own
#' embedding) differs from the baseline in two ways at once: a pooled vs.
#' individual embedding, \emph{and} a shrinkage-regularized vs. fixed
#' (alpha = 1) choice-model noise parameter. A win on that comparison alone
#' does not say which component is responsible -- alpha-shrinkage alone
#' could help even if the embedding geometry carries no real
#' cross-participant structure at all, simply by partially pooling a
#' single scalar noise parameter toward a population mean. This function
#' reports all four combinations (own/pooled embedding x alpha=1/shrunk) so
#' that conclusion doesn't have to be taken on faith; see the
#' \code{triplet_choice_and_loss.Rmd} analysis (outside this package, in
#' the lab's own research documentation) this was first worked out in for
#' a worked example on real data, where embedding-pooling alone (holding
#' alpha fixed) already recovered most of the combined effect -- and where
#' that same analysis went on to test whether alpha's regularization
#' needed to be tied to geometric position at all (an earlier design this
#' workflow used) and found no advantage to doing so, which is why alpha
#' is decoupled from position in the current design.
#'
#' There is a second, independent confound even within "embedding-pooling
#' alone": the kernel-smoothed pooled estimate differs from a participant's
#' own embedding both by averaging in other participants \emph{and} by
#' being evaluated at that participant's own recovered \emph{position} --
#' itself a free parameter fit to that participant's own training data. A
#' plain, position-independent grand mean (the same embedding for every
#' participant) isolates the first effect without the second. Comparing it
#' to the position-weighted pooled estimate answers whether a
#' participant's own position is doing anything beyond ordinary
#' variance-reduction from averaging -- on one real dataset analyzed this
#' way, the two were statistically indistinguishable (no evidence of real
#' position-dependent structure, just noise reduction), while on another
#' they were not (the position-weighted estimate did reliably better,
#' consistent with a real individual-differences axis).
#'
#' @return Invisibly, a list with the parsed run (\code{run}), the
#'   convergence diagnostics (\code{position_flags}, \code{alpha_flags}),
#'   and -- when \code{triplet_data} was supplied -- the comparison table
#'   (\code{decomposition}) and the leave-one-out result (\code{loo}, or
#'   \code{NULL} if \code{run_loo_check = FALSE}). Also writes
#'   \code{output_md} and its figures as a side effect.
#'
#' @export
summarize_joint_estimation <- function(output_dir, triplet_data = NULL,
                                        run_loo_check = TRUE,
                                        fit_sample_alg = "random",
                                        val_trialtype = "validation",
                                        oscillation_window = 5,
                                        oscillation_threshold = 0.1,
                                        item_colors = NULL,
                                        n_geometry_panels = 6,
                                        output_md = NULL,
                                        verbose = TRUE) {
  if (is.null(output_md)) output_md <- file.path(output_dir, "summary.md")
  fig_dir <- file.path(dirname(output_md),
                        paste0(tools::file_path_sans_ext(basename(output_md)), "_files"))
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  fig_rel <- function(name) file.path(basename(fig_dir), name)
  fig_path <- function(name) file.path(fig_dir, name)

  if (verbose) cat("Reading", output_dir, "...\n")
  run <- read_joint_manifold_run(output_dir)
  n <- length(run$worker_ids)

  md <- c(
    paste("#", "Joint-manifold estimation summary"),
    "",
    paste0("Source: `", normalizePath(output_dir, winslash = "/", mustWork = FALSE), "`  "),
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
    "",
    "## Run",
    "",
    md_table(data.frame(
      field = c("Participants", "Dimensionality (d)", "Outer iterations", "Mode",
                "Alpha estimation", "Final population mean alpha", "Final tau2 (between-person)",
                "Final geometry bandwidth"),
      value = c(n, run$d, run$n_outer, run$manifest[["mode"]] %||% NA,
                "decoupled (per-person, shrinkage-regularized)",
                round(utils::tail(run$alpha_diag_traj$pop_mean_alpha, 1), 4),
                round(utils::tail(run$alpha_diag_traj$tau2, 1), 4),
                round(utils::tail(run$alpha_diag_traj$bandwidth, 1), 4))
    )),
    ""
  )

  ## ---- Convergence diagnostics ----
  if (verbose) cat("Checking position and alpha convergence...\n")
  flags <- flag_unstable_joint_positions(run$positions_mat, oscillation_window, oscillation_threshold)
  has_alpha_traj <- !all(is.na(run$alpha_mat))
  alpha_flags <- if (has_alpha_traj) {
    flag_unstable_joint_alpha(run$alpha_mat, oscillation_window, oscillation_threshold)
  } else {
    data.frame(worker_id = run$worker_ids, final_alpha = NA_real_, recent_log_range = NA_real_,
               last_log_change = NA_real_, flagged = FALSE)
  }

  grDevices::png(fig_path("position_trajectory.png"), width = 7, height = 5.5, units = "in", res = 120)
  graphics::par(mar = c(5, 5, 3, 2))
  graphics::matplot(seq_len(run$n_outer), t(run$positions_mat), type = "l", lty = 1,
                     col = ifelse(flags$flagged, "firebrick", grDevices::adjustcolor("gray40", alpha.f = 0.6)),
                     xlab = "Outer iteration", ylab = "Manifold position",
                     main = "Per-participant position trajectories")
  if (any(flags$flagged)) {
    graphics::legend("topleft", legend = "possibly not converged (see table)",
                      col = "firebrick", lty = 1, bty = "n")
  }
  grDevices::dev.off()

  md <- c(md,
    "## Convergence",
    "",
    "Position and alpha are estimated independently now (see *Why the decomposition* in ",
    "`?summarize_joint_estimation`), so each gets its own convergence check.",
    "",
    paste0("![Position trajectories](", fig_rel("position_trajectory.png"), ")"),
    ""
  )

  if (has_alpha_traj) {
    grDevices::png(fig_path("alpha_trajectory.png"), width = 7, height = 5.5, units = "in", res = 120)
    graphics::par(mar = c(5, 5, 3, 2))
    graphics::matplot(seq_len(run$n_outer), t(log10(run$alpha_mat)), type = "l", lty = 1,
                       col = ifelse(alpha_flags$flagged, "firebrick", grDevices::adjustcolor("gray40", alpha.f = 0.6)),
                       xlab = "Outer iteration", ylab = expression(log[10](alpha)),
                       main = "Per-participant alpha trajectories")
    graphics::abline(h = 0, col = "steelblue", lty = 2)
    if (any(alpha_flags$flagged)) {
      graphics::legend("topleft", legend = "possibly not converged (see table)",
                        col = "firebrick", lty = 1, bty = "n")
    }
    grDevices::dev.off()

    grDevices::png(fig_path("alpha_diag_trajectory.png"), width = 7, height = 5, units = "in", res = 120)
    graphics::par(mar = c(5, 5, 3, 2), mfrow = c(1, 2))
    graphics::plot(run$alpha_diag_traj$iter, run$alpha_diag_traj$pop_mean_alpha, type = "b", pch = 16,
                   xlab = "Outer iteration", ylab = "Population mean alpha", main = "Population mean alpha")
    graphics::plot(run$alpha_diag_traj$iter, run$alpha_diag_traj$tau2, type = "b", pch = 16,
                   xlab = "Outer iteration", ylab = "tau^2", main = "Between-person variance (tau^2)")
    grDevices::dev.off()

    md <- c(md,
      paste0("![Alpha trajectories](", fig_rel("alpha_trajectory.png"), ")"),
      "",
      paste0("![Population alpha / tau^2 trajectories](", fig_rel("alpha_diag_trajectory.png"), ")"),
      ""
    )
  } else {
    md <- c(md, "No `iterN/alpha.csv` found for any iteration -- this run predates alpha being ",
            "decoupled from position (an older run of this workflow). Skipping the alpha ",
            "convergence plots.", "")
  }

  if (any(flags$flagged)) {
    bad <- flags[flags$flagged, c("worker_id", "final_position", "recent_range", "last_change")]
    bad$final_position <- round(bad$final_position, 4)
    bad$recent_range <- round(bad$recent_range, 4)
    bad$last_change <- round(bad$last_change, 4)
    md <- c(md,
      sprintf("**%d of %d participants' positions had not stabilized** over the last %d iterations (range exceeds %.0f%% of the full-sample position range) and should be treated as unresolved, not converged point estimates:",
              sum(flags$flagged), n, oscillation_window, 100 * oscillation_threshold),
      "",
      md_table(bad),
      ""
    )
  } else {
    md <- c(md, sprintf("All %d participants' positions were stable over the last %d iterations.", n, oscillation_window), "")
  }
  if (has_alpha_traj) {
    if (any(alpha_flags$flagged)) {
      bada <- alpha_flags[alpha_flags$flagged, c("worker_id", "final_alpha", "recent_log_range", "last_log_change")]
      bada$final_alpha <- signif(bada$final_alpha, 4)
      bada$recent_log_range <- round(bada$recent_log_range, 4)
      bada$last_log_change <- round(bada$last_log_change, 4)
      md <- c(md,
        sprintf("**%d of %d participants' alpha estimates had not stabilized** over the last %d iterations (log-alpha range exceeds %.0f%% of the full-sample log-alpha range):",
                sum(alpha_flags$flagged), n, oscillation_window, 100 * oscillation_threshold),
        "",
        md_table(bada),
        ""
      )
    } else {
      md <- c(md, sprintf("All %d participants' alpha estimates were stable over the last %d iterations.", n, oscillation_window), "")
    }
  }

  ## ---- Choice-model shape (alpha) ----
  pos_final <- run$positions_mat[, run$n_outer]
  alpha_final <- run$final_alpha %||% (if (has_alpha_traj) run$alpha_mat[, run$n_outer] else NULL)
  if (!is.null(alpha_final)) {
    grDevices::png(fig_path("alpha_vs_position.png"), width = 7, height = 5, units = "in", res = 120)
    graphics::par(mar = c(5, 5, 3, 2))
    graphics::plot(pos_final, log10(alpha_final[run$worker_ids]), pch = 16,
                   xlab = "Manifold position", ylab = expression(log[10](alpha)),
                   main = "Final alpha vs. position (descriptive only -- not assumed related)")
    graphics::abline(h = 0, col = "steelblue", lty = 2)
    grDevices::dev.off()
    md <- c(md,
      "## Choice-model shape (alpha)",
      "",
      "Alpha is estimated independently per participant (shrinkage-regularized, not a function of ",
      "position) -- the plot below is purely descriptive, showing whether any relationship with ",
      "position is visually apparent, without assuming or fitting one.",
      "",
      paste0("![Alpha vs. position](", fig_rel("alpha_vs_position.png"), ")"),
      ""
    )
  } else {
    md <- c(md, "## Choice-model shape (alpha)", "",
            "Skipped: no final alpha values found in `output_dir` (an older run, or an incomplete one).", "")
  }

  ## ---- Embedding geometry grid ----
  smoothed_source <- run$final_smoothed_embeddings %||% run$final_embeddings
  if (!is.null(smoothed_source) && run$d %in% c(2, 3) && n >= 2) {
    if (verbose) cat("Building embedding-geometry grid...\n")
    traj <- smooth_embedding_trajectory(smoothed_source, pos_final, n_query = n_geometry_panels)
    colors <- item_colors %||% grDevices::rainbow(length(run$item_order))
    if (run$d == 3 && requireNamespace("scatterplot3d", quietly = TRUE)) {
      n_row <- ceiling(sqrt(n_geometry_panels)); n_col <- ceiling(n_geometry_panels / n_row)
      grDevices::png(fig_path("geometry_grid.png"), width = 3 * n_col, height = 3 * n_row, units = "in", res = 120)
      graphics::par(mfrow = c(n_row, n_col))
      for (qi in seq_along(traj$query_points)) {
        X <- traj$embeddings[[qi]]
        scatterplot3d::scatterplot3d(X[, 1], X[, 2], X[, 3], color = colors, pch = 16,
                                      xlab = "", ylab = "", zlab = "", tick.marks = FALSE,
                                      main = sprintf("t = %.2f", traj$query_points[qi]), mar = c(2, 2, 2, 2))
      }
      grDevices::dev.off()
      md <- c(md, "## Embedding geometry across the manifold", "",
              paste0("![Embedding geometry grid](", fig_rel("geometry_grid.png"), ")"), "")
    } else if (run$d == 2) {
      n_row <- ceiling(sqrt(n_geometry_panels)); n_col <- ceiling(n_geometry_panels / n_row)
      grDevices::png(fig_path("geometry_grid.png"), width = 3 * n_col, height = 3 * n_row, units = "in", res = 120)
      graphics::par(mfrow = c(n_row, n_col), mar = c(2, 2, 2, 1))
      for (qi in seq_along(traj$query_points)) {
        X <- traj$embeddings[[qi]]
        graphics::plot(X[, 1], X[, 2], col = colors, pch = 16, xlab = "", ylab = "",
                       main = sprintf("t = %.2f", traj$query_points[qi]))
      }
      grDevices::dev.off()
      md <- c(md, "## Embedding geometry across the manifold", "",
              paste0("![Embedding geometry grid](", fig_rel("geometry_grid.png"), ")"), "")
    } else {
      md <- c(md, "## Embedding geometry across the manifold", "",
              "scatterplot3d is not installed; skipping the d=3 geometry grid.", "")
    }
  } else if (!is.null(smoothed_source) && !(run$d %in% c(2, 3))) {
    md <- c(md, "## Embedding geometry across the manifold", "",
            sprintf("Skipped: no generic plot is defined for d = %s.", run$d), "")
  }

  result <- list(run = run, position_flags = flags, alpha_flags = alpha_flags,
                  decomposition = NULL, loo = NULL)

  ## ---- Held-out validation comparison (requires triplet_data) ----
  if (is.null(triplet_data)) {
    md <- c(md, "## Held-out validation comparison", "",
            "Skipped: no `triplet_data` supplied, so held-out validation trials are not available ",
            "(they are deliberately never passed to the Condor workflow itself). Pass the original ",
            "combined triplet data frame to `summarize_joint_estimation()` to enable this section.", "")
  } else if (is.null(run$original_embeddings) || is.null(run$final_embeddings)) {
    md <- c(md, "## Held-out validation comparison", "",
            "Skipped: original and/or final refit embeddings were not found in `output_dir` ",
            "(an incomplete or still-running run?).", "")
  } else {
    if (verbose) cat("Evaluating held-out validation comparison...\n")
    trials <- build_jm_trial_lists(triplet_data, run$worker_ids, fit_sample_alg, val_trialtype)

    smoothed_emb <- run$final_smoothed_embeddings
    if (is.null(smoothed_emb)) {
      if (verbose) cat("  final_smoothed_embeddings.csv not found -- recomputing from final_embeddings...\n")
      traj <- smooth_embedding_trajectory(run$final_embeddings, pos_final, query_points = pos_final)
      smoothed_emb <- stats::setNames(traj$embeddings, run$worker_ids)
    }
    shrunk_alpha <- run$final_alpha
    if (is.null(shrunk_alpha)) {
      if (verbose) cat("  final_alpha.csv not found -- re-estimating (bounded-grid MLE + shrinkage)...\n")
      shrunk_alpha <- estimate_shrunk_alpha(smoothed_emb, trials$fit_trials)[run$worker_ids]
    }
    log_alpha_shrunk <- log(shrunk_alpha)
    log_alpha_zero <- stats::setNames(rep(0, n), run$worker_ids)

    grand_mean <- run$final_grand_mean_embedding
    if (is.null(grand_mean)) {
      if (verbose) cat("  final_grand_mean_embedding.csv not found -- recomputing from final_embeddings...\n")
      aligned_for_gm <- generalized_procrustes(run$final_embeddings)$aligned
      grand_mean <- Reduce(`+`, aligned_for_gm) / length(aligned_for_gm)
    }
    grand_mean_emb <- stats::setNames(replicate(n, grand_mean, simplify = FALSE), run$worker_ids)

    res_own_a1     <- ckl_validation_eval(run$original_embeddings, log_alpha_zero,   trials$fit_trials, trials$val_trials)
    res_own_ashrunk <- ckl_validation_eval(run$original_embeddings, log_alpha_shrunk, trials$fit_trials, trials$val_trials)
    res_pool_a1    <- ckl_validation_eval(smoothed_emb,            log_alpha_zero,   trials$fit_trials, trials$val_trials)
    res_pool_ashrunk <- ckl_validation_eval(smoothed_emb,          log_alpha_shrunk, trials$fit_trials, trials$val_trials)
    res_grandmean_a1 <- ckl_validation_eval(grand_mean_emb,        log_alpha_zero,   trials$fit_trials, trials$val_trials)

    decomposition <- rbind(
      data.frame(comparison = "(b) alpha alone vs. (a) baseline"),
      data.frame(comparison = "(c) embedding alone vs. (a) baseline"),
      data.frame(comparison = "(d) both vs. (a) baseline"),
      data.frame(comparison = "(d) both vs. (b) alpha alone"),
      data.frame(comparison = "(d) both vs. (c) embedding alone"),
      data.frame(comparison = "(e) grand mean (no position) vs. (a) baseline"),
      data.frame(comparison = "(c) position-weighted pool vs. (e) grand mean")
    )
    decomposition <- cbind(decomposition, rbind(
      compare_jm_conditions(res_own_ashrunk,  res_own_a1),
      compare_jm_conditions(res_pool_a1,      res_own_a1),
      compare_jm_conditions(res_pool_ashrunk, res_own_a1),
      compare_jm_conditions(res_pool_ashrunk, res_own_ashrunk),
      compare_jm_conditions(res_pool_ashrunk, res_pool_a1),
      compare_jm_conditions(res_grandmean_a1, res_own_a1),
      compare_jm_conditions(res_pool_a1,      res_grandmean_a1)
    ))
    result$decomposition <- decomposition

    grDevices::png(fig_path("comparison_scatter.png"), width = 6.5, height = 6, units = "in", res = 120)
    graphics::par(mar = c(5, 5, 3, 2))
    lim <- range(c(res_own_a1$ll, res_pool_ashrunk$ll), na.rm = TRUE)
    graphics::plot(res_own_a1$ll, res_pool_ashrunk$ll, pch = 16, xlim = lim, ylim = lim,
                   xlab = "Baseline: own embedding, alpha=1 (validation logLik)",
                   ylab = "Production: pooled embedding, shrunk alpha (validation logLik)",
                   main = "Production estimate vs. own individual embedding")
    graphics::abline(0, 1, col = "gray50", lty = 2)
    grDevices::dev.off()

    md <- c(md,
      "## Held-out validation comparison",
      "",
      "Own vs. pooled (kernel-smoothed) vs. grand-mean (plain, position-independent average) ",
      "embedding, crossed with alpha fixed at 1 vs. each participant's own shrinkage-regularized, ",
      "decoupled alpha -- see *Why the decomposition, not just one comparison* in ",
      "`?summarize_joint_estimation`. (b) isolates the alpha-shrinkage effect; (c) isolates the ",
      "embedding-pooling effect; (e)/the last row isolate whether a participant's own recovered ",
      "*position* adds anything beyond simply averaging across everyone -- if (c) and (e) are ",
      "indistinguishable, there is no evidence of real position-dependent structure, only noise ",
      "reduction from pooling.",
      "",
      md_table(decomposition),
      "",
      "(`p_acc` is `NA` whenever two conditions share the same embedding and differ only in ",
      "alpha: accuracy is structurally unaffected by alpha for this choice-model family, so the ",
      "paired difference is exactly zero for every participant, not merely non-significant.)",
      "",
      paste0("![Production vs. baseline](", fig_rel("comparison_scatter.png"), ")"),
      ""
    )

    if (run_loo_check) {
      if (verbose) cat("Running fully out-of-sample loo_trajectory_accuracy() check...\n")
      triplet_list <- lapply(run$worker_ids, function(w) {
        triplet_data[as.character(triplet_data$worker_id) == w, ]
      })
      names(triplet_list) <- run$worker_ids
      repdist <- get.rep.dist(run$original_embeddings)
      loo_res <- loo_trajectory_accuracy(repdist, run$original_embeddings, triplet_list,
                                          n_query = min(25, max(5, n - 1)),
                                          trialtype = val_trialtype, verbose = FALSE)
      result$loo <- loo_res
      fsp <- loo_res$full_sample_position
      acc <- loo_res$accuracy
      nq <- ncol(acc)
      loo_r2 <- summary(stats::lm(stats::as.formula("I(acc[, 1] - acc[, nq]) ~ fsp")))$r.squared
      loo_ct <- stats::cor.test(acc[, 1] - acc[, nq], fsp)

      grDevices::png(fig_path("loo_crossover.png"), width = 6.5, height = 6, units = "in", res = 120)
      graphics::par(mar = c(5, 5, 3, 2))
      graphics::plot(0, .5, type = "n", xlim = range(fsp), ylim = c(min(acc) - .05, max(acc) + .05),
                     xlab = "Manifold position (full sample)", ylab = "Accuracy on held-out trials",
                     main = "Fully out-of-sample: embedding geometry alone")
      for (i in seq_along(fsp)) graphics::lines(c(fsp[i], fsp[i]), c(acc[i, 1], acc[i, nq]), col = "gray")
      graphics::points(fsp, acc[, 1],  pch = 16, col = "steelblue")
      graphics::abline(stats::lm(acc[, 1] ~ fsp), col = "steelblue")
      graphics::points(fsp, acc[, nq], pch = 16, col = "firebrick")
      graphics::abline(stats::lm(acc[, nq] ~ fsp), col = "firebrick")
      graphics::abline(h = .5, lty = 2)
      graphics::legend("bottomleft", legend = c("Embedding at one end", "Embedding at other end"),
                        col = c("steelblue", "firebrick"), pch = 16, bty = "n")
      grDevices::dev.off()

      md <- c(md,
        "## Fully out-of-sample confirmation",
        "",
        "`loo_trajectory_accuracy()`: each participant is fully excluded, including from the 1-D ",
        "manifold axis itself, before the embedding used to predict their held-out trials is computed ",
        "-- no self-contribution of any kind, and no alpha flexibility (pure embedding geometry).",
        "",
        sprintf("Crossover R-squared = %.3f (r = %.3f, p = %s).", loo_r2, loo_ct$estimate,
                format(loo_ct$p.value, digits = 3)),
        "",
        paste0("![Leave-one-out crossover](", fig_rel("loo_crossover.png"), ")"),
        ""
      )
    }
  }

  writeLines(md, output_md)
  if (verbose) cat("Wrote", output_md, "\n")
  invisible(result)
}
