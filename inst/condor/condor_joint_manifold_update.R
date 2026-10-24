#!/usr/bin/env Rscript
# Local (NOT a Condor job -- runs once per fold per outer iteration on the
# submit node) update step for the joint geometry+choice-model manifold
# Condor workflow (condor_joint_manifold_workflow.py, same directory).
#
# Takes one fold's pool of newly-refit embeddings (the output of this same
# iteration's condor_joint_manifold_fit.R jobs) and advances that fold's
# manifold state: re-aligns the embeddings (generalized Procrustes), finds
# each pool member's own best position on the resulting 1-D manifold
# (profiled choice-model likelihood against their own fitting trials), and
# refits the shared population curve log(alpha) = beta0 + beta1*position.
#
# This is deliberately NOT submitted to Condor: profiled, GPA, and the
# per-person position search are all cheap (seconds, confirmed directly
# during local validation of this algorithm) -- the real cost is entirely
# in the embedding refits condor_joint_manifold_fit.R does, which is why
# only those are parallelized across the cluster.
#
# Usage (all arguments are --key=value, order doesn't matter):
#   Rscript condor_joint_manifold_update.R \
#     --n_pool=23 --embeddings_dir=iter2/fold0/embeddings \
#     --trials_dir=setup/person_trials --old_positions=iter1/fold0/positions.csv \
#     --old_beta0=0.4 --old_beta1=-0.3 \
#     --output_positions=iter2/fold0/positions.csv \
#     --output_beta=iter2/fold0/beta.csv \
#     --output_aligned_dir=iter2/fold0/aligned
#
# --embeddings_dir / --trials_dir / --output_aligned_dir each hold
# person0.csv, person1.csv, ..., person{n_pool-1}.csv -- positional, not
# named by worker_id, matching this workflow's person-index convention
# (set once by the orchestrator and held fixed for a given fold across
# every outer iteration).
# --old_positions: path to a one-column ("position") CSV with n_pool rows,
#   or the literal string NULL for the very first outer iteration (no
#   previous state to sign-correct against).

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

required <- c("n_pool", "embeddings_dir", "trials_dir", "old_positions", "old_beta0", "old_beta1",
              "output_positions", "output_beta", "output_aligned_dir")
missing <- setdiff(required, names(opt))
if (length(missing)) {
  stop("Missing required arguments: ", paste0("--", missing, collapse = ", "), call. = FALSE)
}

suppressPackageStartupMessages(library(tripletTools))

n_pool    <- as.integer(opt$n_pool)
old_beta0 <- as.numeric(opt$old_beta0)
old_beta1 <- as.numeric(opt$old_beta1)
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
ll_at_t <- function(t, trials, beta0, beta1, pos, bandwidth, aligned_list) {
  X <- embed_at(t, pos, bandwidth, aligned_list)
  d <- dist_fn(X, trials)
  profiled_ll(beta0 + beta1 * t, d$dw2, d$dl2)
}

## ---- Step 1: GPA-align the newly-refit embeddings ----
gpa <- generalized_procrustes(embeddings)
aligned <- gpa$aligned

## ---- Step 2: initial positions from classical MDS on the aligned
## embeddings' own representational distances, sign-corrected against the
## previous iteration's positions (cmdscale's sign is otherwise arbitrary,
## which would otherwise make beta1 flip sign at random across iterations) ----
positions <- cmdscale(get.rep.dist(embeddings), k = 1)[, 1]
if (!identical(opt$old_positions, "NULL")) {
  old_positions <- read.csv(opt$old_positions, stringsAsFactors = FALSE)$position
  if (length(old_positions) == n_pool && cor(positions, old_positions) < 0) {
    positions <- -positions
  }
}

## ---- Step 3: refine each pool member's position via their own profiled
## choice-model likelihood against the current manifold curve (OLD
## beta0/beta1 -- this iteration's curve refit happens after, in step 4) ----
bandwidth <- stats::bw.nrd0(positions)
rng <- range(positions); pad <- 0.3 * diff(rng)
positions <- sapply(seq_along(pool_idx), function(k) {
  optimize(function(t) ll_at_t(t, person_trials[[k]], old_beta0, old_beta1, positions, bandwidth, aligned),
           interval = c(rng[1] - pad, rng[2] + pad), maximum = TRUE, tol = 1e-4)$maximum
})

## ---- Step 4: refit the shared population curve given the refined positions ----
bandwidth <- stats::bw.nrd0(positions)
dw2_list <- vector("list", n_pool); dl2_list <- vector("list", n_pool)
for (k in seq_along(pool_idx)) {
  X <- embed_at(positions[k], positions, bandwidth, aligned)
  d <- dist_fn(X, person_trials[[k]])
  dw2_list[[k]] <- d$dw2; dl2_list[[k]] <- d$dl2
}
neg_ll_beta <- function(beta) {
  la <- beta[1] + beta[2] * positions
  -sum(mapply(function(l, k) profiled_ll(l, dw2_list[[k]], dl2_list[[k]]), la, seq_along(pool_idx)))
}
fit_beta <- optim(c(old_beta0, old_beta1), neg_ll_beta, method = "Nelder-Mead",
                   control = list(maxit = 1500, reltol = 1e-12))
beta0 <- fit_beta$par[1]; beta1 <- fit_beta$par[2]

## ---- Write outputs ----
write.csv(data.frame(position = positions), opt$output_positions, row.names = FALSE)
write.csv(data.frame(beta0 = beta0, beta1 = beta1, bandwidth = bandwidth), opt$output_beta, row.names = FALSE)
for (k in seq_along(pool_idx)) {
  out <- as.data.frame(aligned[[k]])
  names(out) <- paste0("dim_", seq_len(ncol(out)) - 1)
  write.csv(out, file.path(opt$output_aligned_dir, sprintf("person%d.csv", pool_idx[k])), row.names = FALSE)
}

cat(sprintf("[condor_joint_manifold_update] logLik=%.2f beta0=%.4f beta1=%.4f bandwidth=%.4f\n",
            -fit_beta$value, beta0, beta1, bandwidth))
