#!/usr/bin/env Rscript
# Per-job fit script for the joint geometry+choice-model manifold Condor
# workflow (condor_joint_manifold_workflow.py, same directory). Runs inside
# the container. Refits ONE participant's embedding under a SPECIFIC
# choice-model shape (--alpha), warm-started from their current embedding
# (their original CrowdKernel fit on the very first outer iteration, their
# own previous iteration's refit after that).
#
# Bypasses train_embedding()'s CKL-only R wrapper and calls
# compute_embeddings.py's lower-level _fit_offline() directly (via
# reticulate), exactly the pattern already used by
# condor_recovery_fit.R (same directory) -- the only existing code path
# that supports an arbitrary noise-model alpha rather than the fixed
# crowd-kernel default.
#
# Usage (all arguments are --key=value, order doesn't matter):
#   Rscript condor_joint_manifold_fit.R \
#     --train_triplets=train.csv --test_triplets=test.csv \
#     --init_embedding=init.csv --alpha=2.37 \
#     --output=refit.csv --d=3 --seed=1001 \
#     --max_epochs=6000 --tolerance=1e-4 --tol_window=300 --device=cpu
#
# --train_triplets / --test_triplets: CSVs with columns head,winner,loser
#   (0-based item indices, in the fixed canonical item order the whole
#   workflow shares), already split the same way this person's existing
#   individual embedding was originally fit (the sampleSet train/test
#   split), written once by the orchestrator and reused every outer
#   iteration -- this script does no splitting itself.
# --init_embedding: CSV with an "item" column plus one column per
#   coordinate dimension (dim_0, dim_1, ...), in the same canonical item
#   row order as the triplet indices -- used as the literal starting point
#   for gradient descent (a real warm start, not random-noise
#   initialization), which is why later outer iterations converge much
#   faster than the first.
# --alpha: this person's CURRENT choice-model shape, alpha(t_i) =
#   exp(beta0 + beta1 * t_i), computed by the orchestrator from the
#   population curve's state at the start of this outer iteration. Finite
#   alpha uses the Student-t ("TSTE") noise model; alpha > 1e5 (or
#   literally Inf) is treated as the exact Gaussian limit ("STE").

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

required <- c("train_triplets", "test_triplets", "init_embedding", "alpha", "output", "d",
              "seed", "max_epochs", "tolerance", "tol_window", "device")
missing <- setdiff(required, names(opt))
if (length(missing)) {
  stop("Missing required arguments: ", paste0("--", missing, collapse = ", "), call. = FALSE)
}

# Must load the package (not just system.file() its python/ dir below) --
# tripletTools's own .onLoad() is what activates the "triplet-embeddings"
# conda env via reticulate::use_condaenv(); skipping this left reticulate
# with no configured Python on a real deployment, which made it silently
# auto-bootstrap an empty one via uv instead (ModuleNotFoundError: no
# module named 'pandas') rather than using the container's real env with
# torch/pandas/etc. already installed. Every other per-job fit script in
# this directory already does this -- this one was just missing it.
suppressPackageStartupMessages(library(tripletTools))

d          <- as.integer(opt$d)
seed       <- as.integer(opt$seed)
max_epochs <- as.integer(opt$max_epochs)
tolerance  <- as.numeric(opt$tolerance)
tol_window <- as.integer(opt$tol_window)
device     <- if (opt$device %in% c("NULL", "NA", "")) NULL else opt$device
alpha      <- as.numeric(opt$alpha)  # "Inf" parses correctly to Inf

init_raw <- read.csv(opt$init_embedding, stringsAsFactors = FALSE)
items    <- init_raw$item
init_mat <- as.matrix(init_raw[, setdiff(names(init_raw), "item"), drop = FALSE])
n_items  <- nrow(init_mat)
if (ncol(init_mat) != d) {
  stop(sprintf("--init_embedding has %d coordinate columns, expected d=%d", ncol(init_mat), d),
       call. = FALSE)
}

read_triplets <- function(path) {
  tr <- read.csv(path, stringsAsFactors = FALSE)
  required_cols <- c("head", "winner", "loser")
  if (!all(required_cols %in% names(tr))) {
    stop(sprintf("%s must have columns head,winner,loser", path), call. = FALSE)
  }
  as.matrix(tr[, required_cols])
}
X_train <- read_triplets(opt$train_triplets)
X_test  <- read_triplets(opt$test_triplets)

set.seed(seed)
compute_py <- reticulate::import_from_path(
  "compute_embeddings",
  path = system.file("python", package = "tripletTools")
)
np <- reticulate::import("numpy")
init_np <- np$array(init_mat, dtype = np$float32)

if (is.infinite(alpha) || alpha > 1e5) {
  noise_model <- "STE"
  kwargs <- reticulate::dict()
} else {
  noise_model <- "TSTE"
  kwargs <- reticulate::dict(module__alpha = alpha)
}

res <- compute_py$"_fit_offline"(
  np$array(X_train, dtype = np$int32), np$array(X_test, dtype = np$int32),
  n = as.integer(n_items), d = d,
  max_epochs = max_epochs, tolerance = tolerance,
  tol_window = tol_window, print_every = max_epochs,
  device = device, noise_model = noise_model, embedding = init_np,
  random_state = seed, module_kwargs = kwargs
)
recovered <- res[[1]]

out <- cbind(item = items, as.data.frame(recovered))
names(out) <- c("item", paste0("dim_", seq_len(d) - 1))
write.csv(out, opt$output, row.names = FALSE)
