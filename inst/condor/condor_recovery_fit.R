#!/usr/bin/env Rscript
# Per-job fit script for the choice-model recovery-sweep Condor workflow
# (condor_recovery_sweep_workflow.py, same directory). Runs inside the
# container. Fits ONE embedding from ONE pre-simulated triplet set, using
# a specified fitting choice model (parameterized by --fit_alpha on the
# Student-t continuum: finite alpha = Student-t kernel, alpha=1 exactly
# Crowd Kernel with mu=1; alpha=Inf = the exact Gaussian/gamma=0.5 limit),
# scores recovery against the known ground-truth embedding via Procrustes
# distance, and writes a single-row result CSV plus a companion
# "*_history.csv" holding the per-score_every-epoch training trace (test
# loss, accuracy, norm ratio) for diagnosing early-stopping behavior.
#
# Bypasses train_embedding()'s CKL-only R wrapper and calls
# compute_embeddings.py's lower-level _fit_offline() directly (via
# reticulate) so that any noise model / alpha can be selected -- the same
# approach used in the local scratch validation that this workflow scales
# up. get.rep.dist() (an ordinary exported tripletTools R function) scores
# the recovered embedding against ground truth.
#
# Usage (all arguments are --key=value, order doesn't matter):
#   Rscript condor_recovery_fit.R \
#     --triplets=triplets_rep0_gen1.csv --ground_truth=ground_truth_rep0.csv \
#     --replicate=0 --gen_alpha=1 --fit_alpha=2 --output=result_rep0_gen1fit2.csv \
#     --d=3 --seed=2101 --test_frac=0.1 \
#     --max_epochs=60000 --tolerance=1e-4 --tol_window=3000 --device=cpu
#
# --triplets: CSV with columns head,winner,loser (0-based item indices),
#   already simulated under --gen_alpha (from this job's own replicate's
#   ground truth) by the orchestrator -- this script does no simulation
#   itself, only fitting and scoring.
# --ground_truth: CSV with an "item" column plus one column per coordinate
#   dimension (dim_0, dim_1, ...), also written by the orchestrator -- one
#   per replicate, since each replicate has its own independently
#   simulated ground truth.
# --replicate and --gen_alpha are not used in the fit itself -- they are
#   only echoed into the output row so the aggregation step can group
#   results by replicate and build the gen x fit error matrix without
#   having to parse them back out of a filename.

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

required <- c("triplets", "ground_truth", "replicate", "gen_alpha", "fit_alpha", "output", "d",
              "seed", "test_frac", "max_epochs", "tolerance", "tol_window", "device")
missing <- setdiff(required, names(opt))
if (length(missing)) {
  stop("Missing required arguments: ", paste0("--", missing, collapse = ", "), call. = FALSE)
}

suppressPackageStartupMessages(library(tripletTools))

d          <- as.integer(opt$d)
seed       <- as.integer(opt$seed)
test_frac  <- as.numeric(opt$test_frac)
max_epochs <- as.integer(opt$max_epochs)
tolerance  <- as.numeric(opt$tolerance)
tol_window <- as.integer(opt$tol_window)
device     <- if (opt$device %in% c("NULL", "NA", "")) NULL else opt$device
fit_alpha  <- as.numeric(opt$fit_alpha)   # "Inf" parses correctly to Inf

triplets <- read.csv(opt$triplets, stringsAsFactors = FALSE)
gt_raw   <- read.csv(opt$ground_truth, stringsAsFactors = FALSE)
gt_items <- gt_raw$item
gt <- as.matrix(gt_raw[, setdiff(names(gt_raw), "item"), drop = FALSE])
rownames(gt) <- gt_items
n_items <- nrow(gt)

set.seed(seed)
X <- as.matrix(triplets[, c("head", "winner", "loser")])
n <- nrow(X)
test_idx <- sample.int(n, max(1, floor(test_frac * n)))
X_train <- X[-test_idx, , drop = FALSE]
X_test  <- X[test_idx, , drop = FALSE]

init <- matrix(rnorm(n_items * d), n_items, d) * 1e-4

compute_py <- reticulate::import_from_path(
  "compute_embeddings",
  path = system.file("python", package = "tripletTools")
)
np <- reticulate::import("numpy")
init_np <- np$array(init, dtype = np$float32)

if (is.infinite(fit_alpha)) {
  noise_model <- "STE"
  kwargs <- reticulate::dict()
} else {
  noise_model <- "TSTE"
  kwargs <- reticulate::dict(module__alpha = fit_alpha)
}

res <- compute_py$"_fit_offline"(
  np$array(X_train, dtype = np$int32), np$array(X_test, dtype = np$int32),
  n = as.integer(n_items), d = as.integer(d),
  max_epochs = max_epochs, tolerance = tolerance,
  tol_window = tol_window, print_every = as.integer(max_epochs),
  device = device, noise_model = noise_model, embedding = init_np,
  random_state = NULL, module_kwargs = kwargs
)
recovered <- res[[1]]
rownames(recovered) <- gt_items

recovery_error <- get.rep.dist(list(truth = gt, recovered = recovered), metric = "sqrt_ss")[1, 2]

out <- data.frame(
  replicate      = opt$replicate,
  gen_alpha      = opt$gen_alpha,
  fit_alpha      = opt$fit_alpha,
  recovery_error = recovery_error,
  loss           = res[[2]],
  epoch          = res[[3]]
)
write.csv(out, opt$output, row.names = FALSE)

# Per-score_every-epoch training trace (epoch, train/test loss, train/test
# acc, max/median norm, norm_ratio) -- computed internally by _fit_offline
# regardless, but previously discarded here. Written alongside the main
# single-row result so the loss trajectory (not just its final value) is
# available for diagnosing early-stopping behavior without having to rerun
# anything.
history <- as.data.frame(res[[5]])
write.csv(history, sub("\\.csv$", "_history.csv", opt$output), row.names = FALSE)
