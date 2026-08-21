#!/usr/bin/env Rscript
# Per-job fit script for the tripletTools group-difference Condor workflow
# (condor_group_diff_workflow.py, same directory). Runs inside the
# container; fits ONE group embedding for one side (a real group, or one
# side of a null-permutation pseudo-group) of one replicate, and writes the
# embedding to a CSV. The workflow submits one job per (replicate, side)
# pair -- the true split contributes 2 jobs, and each null permutation
# contributes 2 more.
#
# Usage (all arguments are --key=value, order doesn't matter):
#   Rscript condor_group_fit.R \
#     --triplet_data=side_data.csv \
#     --output=embedding.csv \
#     --d=5 --seed=1003 \
#     --max_epochs=50000 --tolerance=1e-4 --tol_window=10000 \
#     --device=cpu --geometry=euclidean --radius=1 --norm_penalty=0
#
# --triplet_data must already be filtered to just this side's participants
# -- condor_group_diff_workflow.py writes one such filtered CSV per
# (replicate, side) pair before submitting any jobs. This script does no
# participant filtering itself, only fitting.
#
# --d is fixed across every job in the workflow (chosen beforehand, e.g. via
# a local estimate_dimensionality() run on the pooled data) -- re-selecting
# it per replicate would be prohibitively slow and would entangle
# dimensionality selection with the group-difference test itself.

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

required <- c("triplet_data", "output", "d", "seed", "max_epochs", "tolerance",
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

embedding_out <- cbind(item = rownames(out$embedding), as.data.frame(out$embedding))
write.csv(embedding_out, opt$output, row.names = FALSE)
