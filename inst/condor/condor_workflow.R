#!/usr/bin/env Rscript
# tripletTools Condor workflow driver
#
# Runs, on an HTCondor cluster via future.batchtools, in order:
#   1. estimate_dimensionality()          -> dimensionality_{results,summary}.csv
#   2. estimate_learning_curve() at best_d -> learning_curve_{results,summary}.csv
#   3. run_group_embedding_from_list() on the full dataset, at best_d
#      -> best_embedding.csv, best_embedding_history.csv
#
# best_d is read from stage 1's summary$best_d column and used unchanged in
# stages 2 and 3, so the three stages describe one coherent embedding space.
#
# Usage:
#   Rscript condor_workflow.R <triplet_data.rds> <config.yml>
#
# <triplet_data.rds> must contain a named list of participant data frames,
# each with columns Center, Left, Right, Answer, sampleAlg, sampleSet -- the
# same format get.combined() returns and icon_triplets uses. Save one with
# e.g. saveRDS(my_triplet_list, "triplet_data.rds").
#
# <config.yml> follows params_template.yml in this same directory.
#
# This script only orchestrates: every actual embedding fit is dispatched
# as a Condor job via future.batchtools, so it's safe to run this directly
# on a CHTC submit node inside a persistent session (screen/tmux/nohup),
# rather than as a Condor job itself. See the "HTCondor cluster" section of
# the embedding_vignette for one-time cluster setup (a copy of condor.tmpl
# on the submit node, and R/tripletTools/the conda env available on
# execute nodes).

.script_dir <- function() {
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg)) return(dirname(sub("^--file=", "", file_arg)))
  "."
}
source(file.path(.script_dir(), "condor_helpers.R"))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("Usage: Rscript condor_workflow.R <triplet_data.rds> <config.yml>", call. = FALSE)
}
data_path   <- args[[1]]
config_path <- args[[2]]

if (!requireNamespace("yaml", quietly = TRUE)) {
  stop("Package 'yaml' is required to read the config file. Install with install.packages('yaml').", call. = FALSE)
}
if (!requireNamespace("future.batchtools", quietly = TRUE)) {
  stop("Package 'future.batchtools' is required to submit jobs to HTCondor. Install with install.packages('future.batchtools').", call. = FALSE)
}
library(tripletTools)

config <- yaml::read_yaml(config_path)

triplet_list <- readRDS(data_path)
if (!is.list(triplet_list) || is.null(names(triplet_list))) {
  stop("triplet_data.rds must contain a named list of participant data frames (as returned by get.combined()).", call. = FALSE)
}

output_dir <- config$output_dir %||% "condor_output"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

seed     <- config$seed %||% 1L
geometry <- config$geometry %||% "euclidean"
radius   <- config$radius %||% 1
norm_penalty <- config$norm_penalty %||% 0

n_items <- length(unique(unlist(lapply(triplet_list, function(df) c(df$Center, df$Left, df$Right)))))
cat(sprintf(
  "[condor_workflow] %d items, %d participants, geometry = %s, norm_penalty = %s\n",
  n_items, length(triplet_list), geometry, norm_penalty
))

condor_cfg <- config$condor
if (is.null(condor_cfg)) {
  stop("config.yml must include a 'condor:' section (template, workers). See params_template.yml.", call. = FALSE)
}
template <- path.expand(condor_cfg$template %||% "~/.batchtools.condor.tmpl")
if (!file.exists(template)) {
  stop(sprintf(
    "Condor template not found at %s. Copy inst/condor/condor.tmpl there and adjust for your site (see the vignette's HTCondor section).",
    template
  ), call. = FALSE)
}
workers <- condor_cfg$workers %||% 20L

.set_plan <- function(resources) {
  future::plan(future.batchtools::batchtools_condor,
               workers = workers, template = template, resources = resources)
}
on.exit(future::plan(future::sequential), add = TRUE)

# ---- Stage 1: dimensionality search ----------------------------------------
cat("[condor_workflow] Stage 1: estimating dimensionality...\n")
dim_cfg <- config$dimensionality %||% list()
.set_plan(resources_config(dim_cfg, config))

dim_est <- estimate_dimensionality(
  triplet_list        = triplet_list,
  dims                = parse_dims(dim_cfg$dims %||% "1:8"),
  n_restarts          = get_config(dim_cfg, "n_restarts", config, 10L),
  max_epochs          = get_config(dim_cfg, "max_epochs", config, 50000L),
  tolerance           = get_config(dim_cfg, "tolerance", config, 1e-4),
  tol_window          = get_config(dim_cfg, "tol_window", config, 10000L),
  device              = get_config(dim_cfg, "device", config, "cpu"),
  seed                = seed,
  verbose             = TRUE,
  group               = TRUE,
  geometry            = geometry,
  radius              = radius,
  norm_penalty        = norm_penalty,
  best_d_norm_penalty = dim_cfg$best_d_norm_penalty %||% 0
)

write.csv(dim_est$results, file.path(output_dir, "dimensionality_results.csv"), row.names = FALSE)
write.csv(dim_est$summary, file.path(output_dir, "dimensionality_summary.csv"), row.names = FALSE)

best_d <- dim_est$summary$d[dim_est$summary$best_d]
if (length(best_d) != 1L) {
  stop("Could not uniquely determine best_d from the dimensionality summary.", call. = FALSE)
}
cat(sprintf("[condor_workflow] Selected best_d = %d\n", best_d))

# ---- Stage 2: learning curve at best_d -------------------------------------
cat("[condor_workflow] Stage 2: estimating learning curve...\n")
lc_cfg <- config$learning_curve %||% list()
.set_plan(resources_config(lc_cfg, config))

curve <- estimate_learning_curve(
  triplet_list = triplet_list,
  d            = best_d,
  by           = get_config(lc_cfg, "by", config, 0.1),
  n_restarts   = get_config(lc_cfg, "n_restarts", config, 10L),
  max_epochs   = get_config(lc_cfg, "max_epochs", config, 50000L),
  tolerance    = get_config(lc_cfg, "tolerance", config, 1e-4),
  tol_window   = get_config(lc_cfg, "tol_window", config, 10000L),
  device       = get_config(lc_cfg, "device", config, "cpu"),
  seed         = seed,
  verbose      = TRUE,
  group        = TRUE,
  norm_penalty = norm_penalty
)

write.csv(curve$results, file.path(output_dir, "learning_curve_results.csv"), row.names = FALSE)
write.csv(curve$summary, file.path(output_dir, "learning_curve_summary.csv"), row.names = FALSE)

# ---- Stage 3: final embedding on the full dataset --------------------------
# A dedicated fit rather than reusing a fraction = 1.0 restart from stage 2:
# estimate_learning_curve() still holds out a test set at every fraction
# (by design, so hold-out loss is comparable across fractions), but the
# production embedding should use ordinary train/test early stopping over
# *all* available data, the same as any other run_group_embedding_from_list()
# call.
cat("[condor_workflow] Stage 3: fitting the final embedding on the full dataset...\n")
ff_cfg <- config$final_fit %||% list()
.set_plan(resources_config(ff_cfg, config))

final_fit <- future::value(future::future({
  run_group_embedding_from_list(
    triplet_list = triplet_list,
    d            = best_d,
    max_epochs   = get_config(ff_cfg, "max_epochs", config, 50000L),
    tolerance    = get_config(ff_cfg, "tolerance", config, 1e-4),
    tol_window   = get_config(ff_cfg, "tol_window", config, 10000L),
    device       = get_config(ff_cfg, "device", config, "cpu"),
    seed         = seed,
    geometry     = geometry,
    radius       = radius,
    norm_penalty = norm_penalty
  )
}))

embedding_out <- cbind(item = rownames(final_fit$embedding), as.data.frame(final_fit$embedding))
write.csv(embedding_out, file.path(output_dir, "best_embedding.csv"), row.names = FALSE)
write.csv(final_fit$history, file.path(output_dir, "best_embedding_history.csv"), row.names = FALSE)

# ---- Manifest ---------------------------------------------------------------
manifest <- c(
  sprintf("tripletTools version: %s", as.character(utils::packageVersion("tripletTools"))),
  sprintf("Run finished:         %s", format(Sys.time(), tz = "UTC", usetz = TRUE)),
  sprintf("triplet_data:         %s", normalizePath(data_path, mustWork = FALSE)),
  sprintf("config:               %s", normalizePath(config_path, mustWork = FALSE)),
  sprintf("n_items:              %d", n_items),
  sprintf("n_participants:       %d", length(triplet_list)),
  sprintf("geometry:             %s", geometry),
  sprintf("norm_penalty:         %s", norm_penalty),
  sprintf("best_d:               %d", best_d),
  sprintf("best_loss:            %s", final_fit$loss)
)
writeLines(manifest, file.path(output_dir, "run_manifest.txt"))

cat(sprintf("[condor_workflow] Done. Outputs written to %s/\n", output_dir))
