#!/usr/bin/env Rscript
# Per-job comparison script for the tripletTools group-difference Condor
# workflow (condor_group_diff_workflow.py, same directory). Runs inside the
# container; reads one replicate's two already-fitted side embeddings and
# writes ONE result row with their Procrustes correlation. The workflow
# submits one of these jobs per replicate (the true split plus every null
# permutation), only after every condor_group_fit.R job from the earlier
# fitting stage has completed.
#
# Usage:
#   Rscript condor_group_compare.R \
#     --embedding_a=embedding_repN_sideA.csv \
#     --embedding_b=embedding_repN_sideB.csv \
#     --output=compare_repN.csv \
#     --replicate_id=N --is_true=TRUE|FALSE
#
# correlation is 1 - get.rep.dist()'s distance -- the same Procrustes
# correlation convention used throughout tripletTools (e.g. the
# "Comparing Triplet Embeddings" vignette), computed via get.rep.dist()
# itself rather than re-deriving the ss -> correlation formula here.

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

required <- c("embedding_a", "embedding_b", "output", "replicate_id", "is_true")
missing <- setdiff(required, names(opt))
if (length(missing)) {
  stop("Missing required arguments: ", paste0("--", missing, collapse = ", "), call. = FALSE)
}

suppressPackageStartupMessages(library(tripletTools))

read_embedding <- function(path) {
  df <- read.csv(path, stringsAsFactors = FALSE)
  m <- as.matrix(df[, grepl("^dim_", names(df)), drop = FALSE])
  rownames(m) <- df$item
  m
}

emb_a <- read_embedding(opt$embedding_a)
emb_b <- read_embedding(opt$embedding_b)

if (!setequal(rownames(emb_a), rownames(emb_b))) {
  stop("The two embeddings do not contain the same set of items.")
}
emb_b <- emb_b[rownames(emb_a), , drop = FALSE]

sdist <- get.rep.dist(list(a = emb_a, b = emb_b))
correlation <- 1 - sdist[1, 2]

result <- data.frame(
  replicate_id = as.integer(opt$replicate_id),
  is_true      = as.logical(opt$is_true),
  correlation  = correlation,
  stringsAsFactors = FALSE
)
write.csv(result, opt$output, row.names = FALSE)
