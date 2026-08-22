#!/usr/bin/env Rscript
# Per-job fit script for the tripletTools per-participant Condor workflow
# (condor_individual_embeddings_workflow.py, same directory). Runs inside
# the container; fits ONE participant's individual embedding from their own
# triplet judgments only, and writes it to a CSV tagged with worker_id. The
# workflow submits one job per unique worker_id in the input triplet data.
#
# Usage (all arguments are --key=value, order doesn't matter):
#   Rscript condor_individual_fit.R \
#     --triplet_data=worker_data.csv \
#     --worker_id=w042 \
#     --output=embedding_w042.csv \
#     --d=5 --seed=1003 \
#     --max_epochs=50000 --tolerance=1e-4 --tol_window=10000 \
#     --device=cpu --geometry=euclidean --radius=1 --norm_penalty=0
#
# --triplet_data must already be filtered to just this one worker's rows --
# condor_individual_embeddings_workflow.py writes one such filtered CSV per
# worker before submitting any jobs. This script does no participant
# filtering itself, only fitting.
#
# --worker_id tags the output CSV's worker_id column (and appears in error
# messages); it does not affect the fit itself, which is already fully
# determined by --triplet_data's contents. A mismatch between --worker_id
# and what's actually in --triplet_data would be an orchestrator bug, so
# this script cross-checks the two and fails loudly rather than silently
# tagging a fit with the wrong ID.
#
# --d is fixed across every job in the workflow (chosen beforehand, e.g.
# via a local estimate_dimensionality() run pooling all participants) so
# that every participant's embedding shares the same dimensionality and
# stays directly comparable.

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

required <- c("triplet_data", "worker_id", "output", "d", "seed", "max_epochs", "tolerance",
              "tol_window", "device", "geometry", "radius", "norm_penalty")
missing <- setdiff(required, names(opt))
if (length(missing)) {
  stop("Missing required arguments: ", paste0("--", missing, collapse = ", "), call. = FALSE)
}

suppressPackageStartupMessages(library(tripletTools))

d            <- as.integer(opt$d)
seed         <- as.integer(opt$seed)
max_epochs   <- as.integer(opt$max_epochs)
tolerance    <- as.numeric(opt$tolerance)
tol_window   <- as.integer(opt$tol_window)
device       <- if (opt$device %in% c("NULL", "NA", "")) NULL else opt$device
geometry     <- opt$geometry
radius       <- as.numeric(opt$radius)
norm_penalty <- as.numeric(opt$norm_penalty)

triplet_list <- get.combined(opt$triplet_data)

if (length(triplet_list) != 1L || !identical(names(triplet_list), opt$worker_id)) {
  stop(sprintf(
    "Expected %s to contain only worker_id '%s', found %d worker(s) (%s). condor_individual_embeddings_workflow.py should have filtered this file to a single worker.",
    opt$triplet_data, opt$worker_id, length(triplet_list), paste(names(triplet_list), collapse = ", ")
  ), call. = FALSE)
}

out <- run_group_embedding_from_list(
  triplet_list = triplet_list,
  d            = d,
  max_epochs   = max_epochs,
  tolerance    = tolerance,
  tol_window   = tol_window,
  seed         = seed,
  device       = device,
  geometry     = geometry,
  radius       = radius,
  norm_penalty = norm_penalty
)

embedding_out <- cbind(
  worker_id = opt$worker_id,
  item      = rownames(out$embedding),
  as.data.frame(out$embedding)
)
write.csv(embedding_out, opt$output, row.names = FALSE)
