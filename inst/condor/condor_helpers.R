# Small config-handling helpers shared by condor_workflow.R, factored out
# here so they can be sourced and unit-tested independently of the full
# CLI script (which requires command-line args, yaml, and
# future.batchtools to run at all).

`%||%` <- function(a, b) if (is.null(a)) b else a

# Look up `field` in a stage-specific config block first (e.g.
# config$dimensionality), falling back to config$defaults, then to
# `default`. This is how dimensionality:/learning_curve:/final_fit: blocks
# in params_template.yml inherit shared settings while still allowing
# per-stage overrides.
get_config <- function(stage_cfg, field, config, default = NULL) {
  if (!is.null(stage_cfg[[field]])) return(stage_cfg[[field]])
  if (!is.null(config$defaults[[field]])) return(config$defaults[[field]])
  default
}

resources_config <- function(stage_cfg, config) {
  stage_cfg$resources %||% config$defaults$resources %||% list()
}

# Accept either a YAML list (dims: [1, 2, 3]) or an R range string
# (dims: "1:8") for convenience.
parse_dims <- function(x) {
  if (is.character(x) && length(x) == 1L && grepl("^\\s*-?\\d+\\s*:\\s*-?\\d+\\s*$", x)) {
    return(eval(parse(text = x)))
  }
  as.integer(unlist(x))
}

# Load triplet data from either:
#   .csv  a combined CSV in the format get.combined() reads (one row per
#         triplet judgment, with a worker_id column identifying each
#         participant) -- dispatched to get.combined(), which tripletTools
#         must already be loaded/attached for.
#   .rds  a saved named list of participant data frames (the same object
#         get.combined() itself returns).
# Either way the result is the triplet_list format estimate_dimensionality()/
# estimate_learning_curve()/run_group_embedding_from_list() expect.
load_triplet_data <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "csv") {
    get.combined(path)
  } else if (ext == "rds") {
    readRDS(path)
  } else {
    stop(sprintf(
      "Unrecognized triplet data file extension '.%s' for %s -- use .csv (read via get.combined()) or .rds (a saved triplet_list).",
      ext, path
    ), call. = FALSE)
  }
}
