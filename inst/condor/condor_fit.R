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
#     --base_seed=1 --random_state=1003 \
#     --max_epochs=50000 --tolerance=1e-4 --tol_window=10000 \
#     --device=cpu --geometry=euclidean --radius=1 --norm_penalty=0
#
# --base_seed vs --random_state: base_seed must be identical across every
# job in a stage -- it's what prepare_triplet_matrices() uses to build
# X_train/X_test (and, for learning_curve, to shuffle the training pool
# before taking nested fraction prefixes), so every job in a stage sees the
# *same* split/shuffle. random_state is unique per (d, restart) or
# (fraction, restart) job and seeds that job's own model fit -- this
# mirrors exactly how estimate_dimensionality()/estimate_learning_curve()
# derive random_state from a shared base seed internally.
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
              "base_seed", "random_state", "max_epochs", "tolerance",
              "tol_window", "device", "geometry", "radius", "norm_penalty")
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

mats    <- prepare_triplet_matrices(triplet_list, seed = base_seed)
X_train <- mats$X_train
X_test  <- mats$X_test

if (opt$stage == "learning_curve") {
  # Reproduce estimate_learning_curve()'s nested-prefix sampling scheme:
  # shuffle the training pool once using base_seed (identical across every
  # fraction/restart job in this stage, so fractions really do nest), then
  # take a cumulative prefix sized to this job's fraction.
  set.seed(base_seed)
  train_df     <- as.data.frame(X_train)[sample(nrow(X_train)), ]
  n_train_pool <- nrow(train_df)
  n_rows       <- max(1L, round(fraction * n_train_pool))
  X_train      <- as.matrix(train_df[seq_len(n_rows), ])
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
                        norm_ratio = row$norm_ratio, stringsAsFactors = FALSE)
} else {
  result <- data.frame(fraction = fraction, n_train = nrow(X_train), restart = restart,
                        loss = row$loss, accuracy = row$accuracy, epoch = row$epoch_best,
                        norm_ratio = row$norm_ratio, stringsAsFactors = FALSE)
}

write.csv(result, opt$output, row.names = FALSE)
