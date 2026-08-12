#!/usr/bin/env Rscript
# Per-job fit script for the tripletTools Condor workflow. Runs inside the
# container; fits ONE embedding restart and writes ONE result row (or, for
# the final stage, the embedding itself) to a CSV. condor_workflow.py
# submits one Condor job per (dimension, restart) or (fraction, restart)
# pair, each running this script with different arguments, plus one job
# for the single final full-dataset fit.
#
# Usage (all arguments are --key=value, order doesn't matter):
#   Rscript condor_fit.R \
#     --stage=dimensionality|learning_curve|final \
#     --triplet_data=triplet_data.csv \
#     --output=result.csv \
#     --d=3 --fraction=NA --restart=1 \
#     --base_seed=1 --random_state=1003 --internal_test_frac=0.1 \
#     --max_epochs=50000 --tolerance=1e-4 --tol_window=10000 \
#     --device=cpu --geometry=euclidean --radius=1 --norm_penalty=0
#
# --base_seed vs --random_state: base_seed must be identical across every
# job in a stage -- it's what prepare_triplet_matrices() uses to build the
# outer sampleSet-based X_train/X_test split, so every job in a stage draws
# from the *same* sampleSet == "train" pool. random_state is unique per
# (d, restart) or (fraction, restart) job and seeds that job's own model fit
# -- this mirrors exactly how estimate_dimensionality()/
# estimate_learning_curve() derive random_state from a shared base seed
# internally.
#
# --internal_test_frac controls sample_internal_test(): every restart draws
# its own fresh internal_test subset of X_train (and, for learning_curve,
# its own nested-fraction shuffle of what's left), seeded by
# split_seed = base_seed + (restart - 1) * 1000 -- restart-dependent but
# NOT d/fraction-dependent, so a given restart's internal_test sample (and
# shuffle order) is identical across d/fraction, while varying genuinely
# restart-to-restart. This is what gives sd_loss a real data-resampling
# component instead of reflecting only optimization noise on one fixed
# split -- see estimate_dimensionality()'s "Internal test set and restart
# variability" section. Required for every stage but only used for
# dimensionality/learning_curve; ignored for stage=final (which uses
# run_group_embedding_from_list()'s own train/test handling, unrelated to
# this).
#
# --fraction is only used for stage=learning_curve; pass NA otherwise.

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

required <- c("stage", "triplet_data", "output", "d", "fraction", "restart",
              "base_seed", "random_state", "internal_test_frac", "max_epochs",
              "tolerance", "tol_window", "device", "geometry", "radius",
              "norm_penalty")
missing <- setdiff(required, names(opt))
if (length(missing)) {
  stop("Missing required arguments: ", paste0("--", missing, collapse = ", "), call. = FALSE)
}
if (!opt$stage %in% c("dimensionality", "learning_curve", "final")) {
  stop("--stage must be one of: dimensionality, learning_curve, final", call. = FALSE)
}

suppressPackageStartupMessages(library(tripletTools))

d            <- as.integer(opt$d)
restart      <- as.integer(opt$restart)
base_seed    <- as.integer(opt$base_seed)
random_state <- as.integer(opt$random_state)
internal_test_frac <- as.numeric(opt$internal_test_frac)
max_epochs   <- as.integer(opt$max_epochs)
tolerance    <- as.numeric(opt$tolerance)
tol_window   <- as.integer(opt$tol_window)
device       <- if (opt$device %in% c("NULL", "NA", "")) NULL else opt$device
geometry     <- opt$geometry
radius       <- as.numeric(opt$radius)
norm_penalty <- as.numeric(opt$norm_penalty)
fraction     <- if (opt$fraction %in% c("NA", "")) NA_real_ else as.numeric(opt$fraction)

triplet_list <- get.combined(opt$triplet_data)

if (opt$stage == "final") {
  # Full-dataset production fit. Uses run_group_embedding_from_list()
  # directly (its own train/test handling, including a 70/30 fallback if
  # sampleSet isn't usable) rather than prepare_triplet_matrices(), the
  # same as a local, non-Condor call to that function would.
  out <- run_group_embedding_from_list(
    triplet_list = triplet_list,
    d            = d,
    max_epochs   = max_epochs,
    tolerance    = tolerance,
    tol_window   = tol_window,
    device       = device,
    seed         = base_seed,
    geometry     = geometry,
    radius       = radius,
    norm_penalty = norm_penalty
  )
  embedding_out <- cbind(item = rownames(out$embedding), as.data.frame(out$embedding))
  write.csv(embedding_out, opt$output, row.names = FALSE)
  write.csv(out$history, sub("\\.csv$", "_history.csv", opt$output), row.names = FALSE)
  quit(status = 0)
}

mats <- prepare_triplet_matrices(triplet_list, seed = base_seed)

# split_seed depends on restart but not d/fraction, so this restart's
# internal_test sample (and, for learning_curve, its nested-fraction
# shuffle order) is identical across every d/fraction in this stage, while
# varying genuinely restart-to-restart -- see the --internal_test_frac
# comment above and estimate_dimensionality()'s "Internal test set and
# restart variability" section.
split_seed <- base_seed + (restart - 1L) * 1000L
split <- sample_internal_test(mats$X_train, frac = internal_test_frac, seed = split_seed)

if (opt$stage == "dimensionality") {
  X_train <- split$X_fit
  X_test  <- split$X_internal_test
} else {
  # learning_curve: reproduce estimate_learning_curve()'s nested-prefix
  # sampling scheme -- reshuffle what's left after the internal_test
  # carve-out (using split_seed again, a second independent deterministic
  # draw), then take a cumulative prefix sized to this job's fraction.
  set.seed(split_seed)
  fit_pool_shuffled <- split$X_fit[sample(nrow(split$X_fit)), , drop = FALSE]
  n_fit_pool        <- nrow(fit_pool_shuffled)
  n_rows            <- max(1L, round(fraction * n_fit_pool))
  X_train           <- fit_pool_shuffled[seq_len(n_rows), , drop = FALSE]
  X_test            <- split$X_internal_test
}

row <- fit_embedding_restart(
  X_train      = X_train,
  X_test       = X_test,
  d            = d,
  random_state = random_state,
  max_epochs   = max_epochs,
  tolerance    = tolerance,
  tol_window   = tol_window,
  device       = device,
  geometry     = if (opt$stage == "learning_curve") "euclidean" else geometry,
  radius       = if (opt$stage == "learning_curve") 1 else radius,
  norm_penalty = norm_penalty
)

if (opt$stage == "dimensionality") {
  result <- data.frame(d = d, restart = restart, loss = row$loss,
                        accuracy = row$accuracy, epoch = row$epoch_stopped,
                        norm_ratio = row$norm_ratio, n_fit = nrow(X_train),
                        n_internal_test = nrow(X_test), stringsAsFactors = FALSE)
} else {
  result <- data.frame(fraction = fraction, n_train = nrow(X_train), restart = restart,
                        loss = row$loss, accuracy = row$accuracy, epoch = row$epoch_best,
                        norm_ratio = row$norm_ratio, n_internal_test = nrow(X_test),
                        stringsAsFactors = FALSE)
}

write.csv(result, opt$output, row.names = FALSE)
