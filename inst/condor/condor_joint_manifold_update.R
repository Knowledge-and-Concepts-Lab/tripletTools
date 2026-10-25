#!/usr/bin/env Rscript
# Per-iteration update step for the joint geometry+choice-model manifold
# Condor workflow (condor_joint_manifold_workflow.py, same directory). Runs
# as its own single-job Condor batch, inside the same container image as
# the embedding-refit jobs (not a local Rscript call on the submit node --
# an earlier version did that, but a real submit node turned out to have no
# R installation and no clear way to add one).
#
# Geometry and choice-model shape (alpha) are estimated independently here,
# NOT tied to a single shared 1-D curve. An earlier coupled design, where
# alpha(t) = exp(beta0 + beta1*t) was a smooth function of the same
# position that determines geometry, was tested directly against this
# decoupled design on two real datasets and found to have no detectable
# predictive advantage on the one dataset where it was shown to matter at
# all, while risking real harm on a dataset whose geometry carries no real
# individual-differences signal (tying alpha to a signal-free axis). See
# the lab's own `triplet_choice_and_loss.Rmd` for the full comparison.
# Geometry pooling by position is retained (real structure was found there,
# on the dataset where this method was validated) -- only alpha's
# estimation is decoupled from it.
#
# Each outer iteration does, in order:
#   1. GPA-align the newly-refit embeddings.
#   2. Compute initial positions via classical MDS on the aligned
#      embeddings' own representational distances (sign-corrected against
#      the previous iteration, since cmdscale's sign is otherwise
#      arbitrary).
#   3. Refine each pool member's position via their own profiled
#      choice-model likelihood -- scored using THEIR OWN current alpha
#      (fixed, not a function of the candidate position), not a shared
#      curve.
#   4. Re-estimate each pool member's own alpha: a per-person profiled MLE
#      (bounded grid, to avoid the real numerical-runaway failure mode an
#      unconstrained per-person MLE has for participants whose own data is
#      highly self-consistent -- confirmed directly, some individual
#      estimates diverged past 1e10 without a bound), then shrunk toward a
#      precision-weighted population mean via a standard random-effects
#      (DerSimonian-Laird) empirical-Bayes estimate of the between-person
#      variance net of estimation noise. A naive unweighted shrinkage
#      estimator was tried first and collapsed to zero between-person
#      variance for both validation datasets -- traced to a few
#      poorly-identified (near-boundary) individuals distorting the
#      variance estimate as much as well-identified ones; the
#      precision-weighted version does not have this problem.
#
# Usage (all arguments are --key=value, order doesn't matter):
#   Rscript condor_joint_manifold_update.R \
#     --n_pool=23 --embeddings_dir=iter2/embeddings \
#     --trials_dir=setup/person_trials --old_positions=iter1/positions.csv \
#     --old_alpha=iter1/alpha.csv \
#     --output_positions=iter2/positions.csv \
#     --output_alpha=iter2/alpha.csv \
#     --output_aligned_dir=iter2/aligned
#
# --embeddings_dir / --trials_dir / --output_aligned_dir each hold
# person0.csv, person1.csv, ..., person{n_pool-1}.csv -- positional, not
# named by worker_id, matching this workflow's person-index convention
# (set once by the orchestrator and held fixed for a given run across
# every outer iteration).
# --old_positions / --old_alpha: path to the previous iteration's output
#   (one-column "position" CSV / alpha.csv with a "log_alpha" column), or
#   the literal string NULL for the very first outer iteration (no
#   previous state to sign-correct against, or to search positions
#   against -- alpha defaults to 1 for everyone in that case, matching
#   what every per-participant embedding was originally fit under).

parse_args <- function(raw) {
  bad <- !grepl("^--[^=]+=", raw)
  if (any(bad)) {
    stop("Arguments must be --key=value; got: ", paste(raw[bad], collapse = ", "), call. = FALSE)
  }
  kv <- sub("^--", "", raw)
  keys <- sub("=.*$", "", kv)
  vals <- sub("^[^=]*=", "", kv)
  setNames(as.list(vals), keys)
}

opt <- parse_args(commandArgs(trailingOnly = TRUE))

required <- c("n_pool", "embeddings_dir", "trials_dir", "old_positions", "old_alpha",
              "output_positions", "output_alpha", "output_aligned_dir")
missing <- setdiff(required, names(opt))
if (length(missing)) {
  stop("Missing required arguments: ", paste0("--", missing, collapse = ", "), call. = FALSE)
}

suppressPackageStartupMessages(library(tripletTools))

n_pool <- as.integer(opt$n_pool)
dir.create(opt$output_aligned_dir, recursive = TRUE, showWarnings = FALSE)

pool_idx <- seq_len(n_pool) - 1L  # 0-based, matches personN.csv naming

read_embedding <- function(path) {
  raw <- read.csv(path, stringsAsFactors = FALSE)
  as.matrix(raw[, setdiff(names(raw), "item"), drop = FALSE])
}
embeddings <- lapply(pool_idx, function(i) read_embedding(file.path(opt$embeddings_dir, sprintf("person%d.csv", i))))

read_trials <- function(path) {
  tr <- read.csv(path, stringsAsFactors = FALSE)
  list(head = tr$head + 1L, winner = tr$winner + 1L, loser = tr$loser + 1L)  # to 1-based for R indexing
}
person_trials <- lapply(pool_idx, function(i) read_trials(file.path(opt$trials_dir, sprintf("person%d.csv", i))))

## ---- Choice-model likelihood helpers (same formulas used throughout this
## investigation's local validation; not package functions -- this
## workflow is self-contained, matching this directory's convention of
## duplicating rather than sharing code between Condor workflows) ----
softplus <- function(x) ifelse(x > 0, x + log1p(exp(-x)), log1p(exp(x)))
sum_log_lik <- function(log_s, log_alpha, dw2u, dl2u) {
  s2 <- exp(2 * log_s); alpha <- exp(log_alpha)
  dw2 <- dw2u * s2; dl2 <- dl2u * s2
  log_tw <- -(alpha + 1) / 2 * log1p(dw2 / alpha)
  log_tl <- -(alpha + 1) / 2 * log1p(dl2 / alpha)
  sum(-softplus(log_tl - log_tw))
}
profiled_ll <- function(log_alpha, dw2u, dl2u) {
  optimize(function(log_s) sum_log_lik(log_s, log_alpha, dw2u, dl2u),
           interval = c(-8, 8), maximum = TRUE, tol = 1e-8)$objective
}
dist_fn <- function(X, trials) {
  list(dw2 = rowSums((X[trials$head, ] - X[trials$winner, ])^2),
       dl2 = rowSums((X[trials$head, ] - X[trials$loser, ])^2))
}
kernel_fn <- function(u) exp(-0.5 * u^2)
embed_at <- function(t, pos, bandwidth, aligned_list) {
  w <- kernel_fn((pos - t) / bandwidth)
  w <- w / sum(w)
  Reduce(`+`, Map(function(mat, wi) mat * wi, aligned_list, w))
}
ll_at_t <- function(t, trials, log_alpha, pos, bandwidth, aligned_list) {
  X <- embed_at(t, pos, bandwidth, aligned_list)
  d <- dist_fn(X, trials)
  profiled_ll(log_alpha, d$dw2, d$dl2)
}

## ---- Step 1: GPA-align the newly-refit embeddings ----
gpa <- generalized_procrustes(embeddings)
aligned <- gpa$aligned

## ---- Step 2: initial positions from classical MDS on the aligned
## embeddings' own representational distances, sign-corrected against the
## previous iteration's positions (cmdscale's sign is otherwise arbitrary) ----
positions <- cmdscale(get.rep.dist(embeddings), k = 1)[, 1]
if (!identical(opt$old_positions, "NULL")) {
  old_positions <- read.csv(opt$old_positions, stringsAsFactors = FALSE)$position
  if (length(old_positions) == n_pool && cor(positions, old_positions) < 0) {
    positions <- -positions
  }
}

## ---- Step 3: refine each pool member's position via their own profiled
## choice-model likelihood against the current geometry pool, scored at
## THEIR OWN current alpha (fixed; not a function of the candidate t) ----
if (!identical(opt$old_alpha, "NULL")) {
  old_log_alpha <- read.csv(opt$old_alpha, stringsAsFactors = FALSE)$log_alpha
  if (length(old_log_alpha) != n_pool) old_log_alpha <- rep(0, n_pool)
} else {
  old_log_alpha <- rep(0, n_pool)  # alpha = 1, matching every embedding's original CrowdKernel fit
}

bandwidth <- stats::bw.nrd0(positions)
rng <- range(positions); pad <- 0.3 * diff(rng)
positions <- sapply(seq_along(pool_idx), function(k) {
  optimize(function(t) ll_at_t(t, person_trials[[k]], old_log_alpha[k], positions, bandwidth, aligned),
           interval = c(rng[1] - pad, rng[2] + pad), maximum = TRUE, tol = 1e-4)$maximum
})

## ---- Step 4: re-estimate each pool member's own alpha: a per-person
## profiled MLE over a bounded grid (avoids the unconstrained-optimizer
## runaway failure mode confirmed for participants whose own data is
## highly self-consistent), then empirical-Bayes shrinkage toward a
## precision-weighted population mean (standard DerSimonian-Laird
## random-effects estimator) ----
bandwidth <- stats::bw.nrd0(positions)
alpha_grid <- 10^seq(log10(2e-4), log10(2e6), length.out = 140)

log_alpha_hat <- numeric(n_pool)
se_log_alpha <- numeric(n_pool)
for (k in seq_along(pool_idx)) {
  X_k <- embed_at(positions[k], positions, bandwidth, aligned)
  d_k <- dist_fn(X_k, person_trials[[k]])
  prof <- sapply(alpha_grid, function(a) profiled_ll(log(a), d_k$dw2, d_k$dl2))
  bi <- which.max(prof)
  log_alpha_hat[k] <- log(alpha_grid[bi])
  in_ci <- prof > (prof[bi] - 1.92)  # 95% profile-likelihood CI (chi-sq(1))
  lo <- min(log(alpha_grid[in_ci])); hi <- max(log(alpha_grid[in_ci]))
  se_log_alpha[k] <- (hi - lo) / (2 * 1.96)  # approx SE from CI width, standard normal-theory conversion
}

w_i <- 1 / se_log_alpha^2
pop_mean_log_alpha <- sum(w_i * log_alpha_hat) / sum(w_i)
Q <- sum(w_i * (log_alpha_hat - pop_mean_log_alpha)^2)
tau2 <- max(0, (Q - (n_pool - 1)) / (sum(w_i) - sum(w_i^2) / sum(w_i)))
w_shrink <- tau2 / (tau2 + se_log_alpha^2)
log_alpha_shrunk <- pop_mean_log_alpha + w_shrink * (log_alpha_hat - pop_mean_log_alpha)

## ---- Write outputs ----
write.csv(data.frame(position = positions), opt$output_positions, row.names = FALSE)
write.csv(data.frame(
  log_alpha = log_alpha_shrunk, alpha = exp(log_alpha_shrunk),
  log_alpha_raw = log_alpha_hat, se_log_alpha = se_log_alpha, shrinkage_weight = w_shrink,
  tau2 = tau2, pop_mean_alpha = exp(pop_mean_log_alpha), bandwidth = bandwidth
), opt$output_alpha, row.names = FALSE)
for (k in seq_along(pool_idx)) {
  out <- as.data.frame(aligned[[k]])
  names(out) <- paste0("dim_", seq_len(ncol(out)) - 1)
  write.csv(out, file.path(opt$output_aligned_dir, sprintf("person%d.csv", pool_idx[k])), row.names = FALSE)
}

total_ll <- sum(sapply(seq_along(pool_idx), function(k) {
  X_k <- embed_at(positions[k], positions, bandwidth, aligned)
  d_k <- dist_fn(X_k, person_trials[[k]])
  profiled_ll(log_alpha_shrunk[k], d_k$dw2, d_k$dl2)
}))
cat(sprintf(
  "[condor_joint_manifold_update] logLik=%.2f pop_mean_alpha=%.4f tau2=%.4f bandwidth=%.4f mean_shrinkage=%.3f\n",
  total_ll, exp(pop_mean_log_alpha), tau2, bandwidth, mean(w_shrink)
))
