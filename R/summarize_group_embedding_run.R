## Internal helpers for summarize_group_embedding_run() ------------------

read_csv_if_exists <- function(path) {
  if (!file.exists(path)) return(NULL)
  utils::read.csv(path, stringsAsFactors = FALSE)
}

read_embedding_csv_if_exists <- function(path) {
  if (!file.exists(path)) return(NULL)
  raw <- utils::read.csv(path, stringsAsFactors = FALSE)
  mat <- as.matrix(raw[, setdiff(names(raw), "item"), drop = FALSE])
  rownames(mat) <- raw$item
  mat
}

## Reads condor_workflow.py's run_manifest.txt the same way
## read_joint_manifold_run() does (first ":" splits key from value, the
## rest is rejoined with ":" so a docker://... URL or an ISO timestamp in
## the value doesn't get truncated at its own internal colons).
read_group_embedding_run <- function(output_dir) {
  manifest_path <- file.path(output_dir, "run_manifest.txt")
  if (!file.exists(manifest_path)) {
    stop("No run_manifest.txt found in ", output_dir,
         " -- is this a condor_workflow.py output directory?")
  }
  manifest <- list()
  for (ln in readLines(manifest_path)) {
    if (!grepl(":", ln, fixed = TRUE)) next
    kv <- strsplit(ln, ":", fixed = TRUE)[[1]]
    manifest[[trimws(kv[1])]] <- trimws(paste(kv[-1], collapse = ":"))
  }

  best_d <- suppressWarnings(as.integer(manifest[["best_d"]]))
  alpha  <- suppressWarnings(as.numeric(manifest[["alpha"]]))

  list(
    output_dir = output_dir,
    manifest = manifest,
    best_d = best_d,
    alpha = alpha,

    dim_results = read_csv_if_exists(file.path(output_dir, "dimensionality_results.csv")),
    dim_summary = read_csv_if_exists(file.path(output_dir, "dimensionality_summary.csv")),

    lc_results = read_csv_if_exists(file.path(output_dir, "learning_curve_results.csv")),
    lc_summary = read_csv_if_exists(file.path(output_dir, "learning_curve_summary.csv")),

    warm_start_embedding = read_embedding_csv_if_exists(file.path(output_dir, "best_embedding.csv")),
    warm_start_history   = read_csv_if_exists(file.path(output_dir, "best_embedding_history.csv")),
    warm_start_restarts  = read_csv_if_exists(file.path(output_dir, "best_embedding_restarts.csv")),

    alpha_result    = read_csv_if_exists(file.path(output_dir, "alpha_result.csv")),
    alpha_history   = read_csv_if_exists(file.path(output_dir, "alpha_history.csv")),
    alpha_embedding = read_embedding_csv_if_exists(file.path(output_dir, "alpha_embedding.csv")),

    final_embedding = read_embedding_csv_if_exists(file.path(output_dir, "best_final_embedding.csv")),
    final_history   = read_csv_if_exists(file.path(output_dir, "best_final_embedding_history.csv")),
    final_restarts  = read_csv_if_exists(file.path(output_dir, "best_final_embedding_restarts.csv"))
  )
}

round_df <- function(df, digits = 4) {
  num_cols <- vapply(df, is.numeric, logical(1))
  df[num_cols] <- lapply(df[num_cols], round, digits)
  df
}

## Train/test loss vs. epoch, as written by condor_fit.R's *_history.csv
## files (epoch, train_loss, test_loss, train_acc, test_acc, max_norm,
## median_norm, norm_ratio) for any of stages 3/5's kept-restart history.
plot_training_history <- function(history, main) {
  graphics::par(mar = c(5, 5, 3, 2))
  ylim <- range(c(history$train_loss, history$test_loss), na.rm = TRUE)
  graphics::plot(history$epoch, history$train_loss, type = "l", col = "steelblue",
                 ylim = ylim, xlab = "Epoch", ylab = "Loss", main = main)
  graphics::lines(history$epoch, history$test_loss, col = "firebrick")
  graphics::legend("topright", legend = c("train", "test"),
                    col = c("steelblue", "firebrick"), lty = 1, bty = "n")
}

## One dot per restart's kept test loss, sorted, with the kept (lowest-loss)
## restart highlighted -- skipped (returns FALSE) when there's only one
## restart, since a one-point "distribution" isn't informative.
plot_restarts <- function(restarts, main) {
  if (nrow(restarts) < 2) return(invisible(FALSE))
  ord <- order(restarts$loss)
  graphics::par(mar = c(5, 5, 3, 2))
  graphics::plot(seq_len(nrow(restarts)), restarts$loss[ord], pch = 16,
                 xlab = "Restart (sorted by test loss)", ylab = "Test loss", main = main)
  graphics::points(1, restarts$loss[ord][1], pch = 16, col = "firebrick", cex = 1.4)
  graphics::legend("topright", legend = "kept restart", pch = 16, col = "firebrick", bty = "n")
  invisible(TRUE)
}

## Generic (no dataset-specific semantics) embedding geometry plot, same
## item_colors convention as summarize_joint_estimation()'s geometry grid:
## colors by row position via rainbow() unless the caller supplies its own.
## Handles d = 1 (a 1-D jittered stripchart; condor_workflow.py's
## dimensionality search routinely selects d = 1 when losses are flat
## across d, so this is a real case, not a hypothetical one) through d = 3
## (scatterplot3d, if installed); returns FALSE (nothing plotted) for any
## other d.
plot_embedding_geometry <- function(embedding, item_colors = NULL, main = "Embedding") {
  d <- ncol(embedding)
  colors <- item_colors %||% grDevices::rainbow(nrow(embedding))
  if (d == 1) {
    # Not graphics::stripchart(): it only honors col[1] for a single
    # (ungrouped) vector of points, silently ignoring a per-point color
    # vector -- confirmed directly, not assumed -- so a manual jittered
    # plot() is used instead to get per-item colors onto the plot at all.
    graphics::par(mar = c(5, 2, 3, 2))
    y <- stats::runif(nrow(embedding), -0.1, 0.1)
    graphics::plot(embedding[, 1], y, pch = 16, col = colors, yaxt = "n",
                   ylim = c(-0.5, 0.5), xlab = "dim_0", ylab = "", main = main)
  } else if (d == 2) {
    graphics::par(mar = c(5, 5, 3, 2))
    graphics::plot(embedding[, 1], embedding[, 2], pch = 16, col = colors,
                   xlab = "dim_0", ylab = "dim_1", main = main)
  } else if (d == 3 && requireNamespace("scatterplot3d", quietly = TRUE)) {
    scatterplot3d::scatterplot3d(embedding[, 1], embedding[, 2], embedding[, 3],
                                  color = colors, pch = 16,
                                  xlab = "dim_0", ylab = "dim_1", zlab = "dim_2", main = main)
  } else {
    return(invisible(FALSE))
  }
  invisible(TRUE)
}

#' Summarize a \code{condor_workflow.py} run
#'
#' Reads the output directory of \code{condor_workflow.py}'s five-stage
#' Condor pipeline (package \code{inst/condor/}; see
#' \code{vignette("condor_workflows_vignette")}'s Workflow 1, and
#' \code{\link{run_group_embedding_workflow}} for the local, non-Condor
#' equivalent) and writes a self-contained Markdown report with one section
#' per stage: the dimensionality search, the learning curve, the
#' crowd-kernel warm-start fit, alpha estimation, and the final-final
#' production fit -- each with the plots this project has repeatedly needed
#' by hand after a real Condor run (loss/accuracy vs. dimension or fraction,
#' training curves, restart stability, the alpha trajectory, and the
#' recovered embedding's own geometry). The same report-generation idea as
#' \code{\link{summarize_joint_estimation}}, for this package's other
#' Condor workflow.
#'
#' Stages 2 (learning curve), 4 (alpha estimation), and 5 (final-final fit)
#' are optional in \code{condor_workflow.py} itself (\code{run_learning_curve:
#' false} / \code{refit_alpha: false} in its config) -- this function detects
#' their absence from \code{output_dir} directly (rather than trusting
#' \code{run_manifest.txt}'s own fields, which an older run may not have) and
#' writes a short note in place of that stage's section instead of failing.
#' When stages 4-5 were skipped, \code{best_embedding.csv} (stage 3) is
#' reported as the production embedding instead of
#' \code{best_final_embedding.csv}, matching
#' \code{vignette("condor_workflows_vignette")}'s own convention.
#'
#' @param output_dir Path to a \code{condor_workflow.py} output directory
#'   (must contain \code{run_manifest.txt}).
#' @param item_colors Character vector, same length and row order as the
#'   production embedding, or \code{NULL} (default): colors for the
#'   embedding-geometry plots. With no dataset-specific semantics available
#'   in general, the default colors items by row position via
#'   \code{\link[grDevices]{rainbow}}; pass a semantically meaningful vector
#'   for a more informative plot.
#' @param output_md Path to write the Markdown report to. Default
#'   \code{file.path(output_dir, "summary.md")}. Figures are written as PNG
#'   files to a sibling \verb{<name>_files/} directory and referenced with
#'   relative paths, so the report is self-contained if copied as a unit.
#' @param verbose Logical, print progress. Default \code{TRUE}.
#'
#' @return Invisibly, the parsed run as a named list (see the source of
#'   \code{read_group_embedding_run()} for its fields) -- mainly useful for
#'   follow-up inspection in an interactive session. Also writes
#'   \code{output_md} and its figures as a side effect.
#'
#' @export
summarize_group_embedding_run <- function(output_dir,
                                           item_colors = NULL,
                                           output_md = NULL,
                                           verbose = TRUE) {
  if (is.null(output_md)) output_md <- file.path(output_dir, "summary.md")
  fig_dir <- file.path(dirname(output_md),
                        paste0(tools::file_path_sans_ext(basename(output_md)), "_files"))
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  fig_rel  <- function(name) file.path(basename(fig_dir), name)
  fig_path <- function(name) file.path(fig_dir, name)

  if (verbose) cat("Reading", output_dir, "...\n")
  run <- read_group_embedding_run(output_dir)

  ran_learning_curve <- !is.null(run$lc_summary)
  ran_alpha_stages    <- !is.null(run$alpha_result) && !is.null(run$final_embedding)
  production_embedding <- if (ran_alpha_stages) run$final_embedding else run$warm_start_embedding
  production_label <- if (ran_alpha_stages) {
    "`best_final_embedding.csv` (Stage 5)"
  } else {
    "`best_embedding.csv` (Stage 3 -- `refit_alpha: false` or an incomplete run, so there is no Stage 5)"
  }

  md <- c(
    "# Group-embedding Condor workflow summary",
    "",
    paste0("Source: `", normalizePath(output_dir, winslash = "/", mustWork = FALSE), "`  "),
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
    "",
    "## Run",
    "",
    md_table(data.frame(
      field = c("triplet_data", "config", "geometry", "norm_penalty",
                "best_d", "alpha", "production embedding"),
      value = c(run$manifest[["triplet_data"]] %||% NA,
                run$manifest[["config"]] %||% NA,
                run$manifest[["geometry"]] %||% NA,
                run$manifest[["norm_penalty"]] %||% NA,
                run$best_d %||% NA,
                if (is.na(run$alpha)) "N/A (refit_alpha: false)" else signif(run$alpha, 6),
                production_label)
    )),
    ""
  )

  ## ---- Stage 1: dimensionality search ----
  if (!is.null(run$dim_summary)) {
    if (verbose) cat("Stage 1 (dimensionality search)...\n")
    n_restarts_dim <- max(table(run$dim_results$d))
    s <- run$dim_summary
    s$best_d <- as.logical(s$best_d)
    se <- s$sd_loss / sqrt(n_restarts_dim)
    se[is.na(se)] <- 0
    cols <- ifelse(s$best_d, "firebrick", "steelblue")

    grDevices::png(fig_path("dimensionality.png"), width = 9, height = 4.5, units = "in", res = 120)
    graphics::par(mfrow = c(1, 2))
    graphics::plot(s$d, s$mean_loss, pch = 16, col = cols,
                   ylim = range(c(s$mean_loss - se, s$mean_loss + se)),
                   xlab = "Dimension (d)", ylab = "Mean test loss (+/- 1 SE)",
                   main = "Dimensionality search: loss")
    graphics::arrows(s$d, s$mean_loss - se, s$d, s$mean_loss + se,
                      angle = 90, code = 3, length = 0.05, col = cols)
    graphics::legend("bottomright", legend = "selected best_d", pch = 16, col = "firebrick", bty = "n")
    graphics::plot(s$d, s$mean_accuracy, pch = 16, col = cols,
                   xlab = "Dimension (d)", ylab = "Mean test accuracy",
                   main = "Dimensionality search: accuracy")
    grDevices::dev.off()

    md <- c(md,
      "## Stage 1: dimensionality search",
      "",
      sprintf("`best_d = %d`, selected via the one-SE parsimony rule (see `?summarize_dimensionality`) across %d restart(s) per dimension.",
              run$best_d, n_restarts_dim),
      "",
      paste0("![Dimensionality search](", fig_rel("dimensionality.png"), ")"),
      "",
      md_table(round_df(s[, c("d", "mean_loss", "sd_loss", "mean_accuracy", "mean_norm_ratio", "best_d")])),
      ""
    )
  } else {
    md <- c(md, "## Stage 1: dimensionality search", "",
            "Skipped: `dimensionality_summary.csv` not found in `output_dir`.", "")
  }

  ## ---- Stage 2: learning curve (optional) ----
  if (ran_learning_curve) {
    if (verbose) cat("Stage 2 (learning curve)...\n")
    n_restarts_lc <- max(table(run$lc_results$fraction))
    s <- run$lc_summary
    se_loss <- s$sd_loss / sqrt(n_restarts_lc); se_loss[is.na(se_loss)] <- 0
    se_acc  <- s$sd_accuracy / sqrt(n_restarts_lc); se_acc[is.na(se_acc)] <- 0

    grDevices::png(fig_path("learning_curve.png"), width = 9, height = 4.5, units = "in", res = 120)
    graphics::par(mfrow = c(1, 2))
    graphics::plot(s$fraction, s$mean_loss, type = "b", pch = 16,
                   ylim = range(c(s$mean_loss - se_loss, s$mean_loss + se_loss)),
                   xlab = "Fraction of training data", ylab = "Mean test loss (+/- 1 SE)",
                   main = "Learning curve: loss")
    graphics::arrows(s$fraction, s$mean_loss - se_loss, s$fraction, s$mean_loss + se_loss,
                      angle = 90, code = 3, length = 0.05)
    graphics::plot(s$fraction, s$mean_accuracy, type = "b", pch = 16,
                   ylim = range(c(s$mean_accuracy - se_acc, s$mean_accuracy + se_acc)),
                   xlab = "Fraction of training data", ylab = "Mean test accuracy (+/- 1 SE)",
                   main = "Learning curve: accuracy")
    graphics::arrows(s$fraction, s$mean_accuracy - se_acc, s$fraction, s$mean_accuracy + se_acc,
                      angle = 90, code = 3, length = 0.05)
    grDevices::dev.off()

    md <- c(md,
      "## Stage 2: learning curve",
      "",
      sprintf("At `best_d = %d`, across %d restart(s) per fraction. A curve still climbing steeply at `fraction = 1.0` suggests more data would likely still help; one that has flattened out suggests the fit already has enough triplets (see `?estimate_learning_curve`).",
              run$best_d, n_restarts_lc),
      "",
      paste0("![Learning curve](", fig_rel("learning_curve.png"), ")"),
      "",
      md_table(round_df(s[, c("fraction", "n_train", "mean_loss", "sd_loss", "mean_accuracy", "sd_accuracy")])),
      ""
    )
  } else {
    md <- c(md, "## Stage 2: learning curve", "",
            "Skipped (`run_learning_curve: false`, or an incomplete run).", "")
  }

  ## ---- Stage 3: crowd-kernel warm-start fit ----
  if (!is.null(run$warm_start_history)) {
    if (verbose) cat("Stage 3 (warm-start fit)...\n")
    grDevices::png(fig_path("stage3_history.png"), width = 7, height = 5, units = "in", res = 120)
    plot_training_history(run$warm_start_history,
                           sprintf("Stage 3: crowd-kernel (alpha=1) fit at d=%d", run$best_d))
    grDevices::dev.off()

    stage3_role <- if (ran_alpha_stages) {
      "This is the **warm-start fit for Stage 4**, not the production embedding."
    } else {
      "Since Stage 4 (alpha estimation) did not run, **this is the production embedding**."
    }

    md <- c(md,
      "## Stage 3: crowd-kernel warm-start fit",
      "",
      stage3_role,
      "",
      paste0("![Stage 3 training history](", fig_rel("stage3_history.png"), ")"),
      ""
    )
    if (!is.null(run$warm_start_restarts) && nrow(run$warm_start_restarts) > 1) {
      grDevices::png(fig_path("stage3_restarts.png"), width = 6, height = 5, units = "in", res = 120)
      plot_restarts(run$warm_start_restarts, "Stage 3 restarts")
      grDevices::dev.off()
      md <- c(md, paste0("![Stage 3 restarts](", fig_rel("stage3_restarts.png"), ")"), "")
    }
  } else {
    md <- c(md, "## Stage 3: crowd-kernel warm-start fit", "",
            "Skipped: `best_embedding_history.csv` not found in `output_dir` (an incomplete run?).", "")
  }

  ## ---- Stage 4: alpha estimation (optional) ----
  if (!is.null(run$alpha_history) && !is.null(run$alpha_result)) {
    if (verbose) cat("Stage 4 (alpha estimation)...\n")
    h <- run$alpha_history
    grDevices::png(fig_path("alpha_history.png"), width = 9, height = 4.5, units = "in", res = 120)
    graphics::par(mfrow = c(1, 2))
    graphics::plot(h$iter, h$alpha, type = "b", pch = 16, log = "y",
                   xlab = "Outer iteration", ylab = "alpha (log scale)",
                   main = "Alpha re-estimate per iteration")
    graphics::plot(h$iter, h$delta_log_alpha, type = "b", pch = 16,
                   xlab = "Outer iteration", ylab = "|delta log(alpha)|",
                   main = "Convergence")
    graphics::abline(h = 0, lty = 2, col = "gray50")
    grDevices::dev.off()

    r <- run$alpha_result
    md <- c(md,
      "## Stage 4: alpha estimation",
      "",
      sprintf("Converged after %d outer iteration(s) to **alpha = %.4g** (95%% profile-likelihood CI [%.4g, %.4g]), profiled on %s alpha-test row(s) (%s row(s) reserved for the embedding refit's own early stopping).",
              nrow(h), r$alpha, r$ci_lo, r$ci_hi, format(r$n_alpha_test, big.mark = ","),
              format(r$n_test_fit, big.mark = ",")),
      "",
      "A confidence bound equal to the point estimate itself is not a bug -- it means the next grid point in that direction already falls outside the 95% band; this profile is routinely asymmetric (see `?estimate_group_alpha`'s \"What this does and does not estimate\" section).",
      "",
      paste0("![Alpha estimation history](", fig_rel("alpha_history.png"), ")"),
      ""
    )
  } else {
    md <- c(md, "## Stage 4: alpha estimation", "",
            "Skipped (`refit_alpha: false`, or an incomplete run).", "")
  }

  ## ---- Stage 5: final-final production fit (optional) ----
  if (!is.null(run$final_history)) {
    if (verbose) cat("Stage 5 (final-final fit)...\n")
    grDevices::png(fig_path("stage5_history.png"), width = 7, height = 5, units = "in", res = 120)
    plot_training_history(run$final_history,
                           sprintf("Stage 5: final-final fit at d=%d, alpha=%.4g", run$best_d, run$alpha))
    grDevices::dev.off()

    md <- c(md,
      "## Stage 5: final-final production fit",
      "",
      "**This is the production embedding.**",
      "",
      paste0("![Stage 5 training history](", fig_rel("stage5_history.png"), ")"),
      ""
    )
    if (!is.null(run$final_restarts) && nrow(run$final_restarts) > 1) {
      grDevices::png(fig_path("stage5_restarts.png"), width = 6, height = 5, units = "in", res = 120)
      plot_restarts(run$final_restarts, sprintf("Stage 5 restarts (n=%d)", nrow(run$final_restarts)))
      grDevices::dev.off()
      md <- c(md,
        sprintf("%d independent random-seed restarts; test loss ranged %.6g to %.6g.",
                nrow(run$final_restarts), min(run$final_restarts$loss), max(run$final_restarts$loss)),
        "",
        paste0("![Stage 5 restarts](", fig_rel("stage5_restarts.png"), ")"), ""
      )
    }
  } else {
    md <- c(md, "## Stage 5: final-final production fit", "",
            "Skipped (`refit_alpha: false`, or an incomplete run).", "")
  }

  ## ---- Production embedding geometry ----
  if (verbose) cat("Production embedding geometry...\n")
  md <- c(md, "## Production embedding", "",
          sprintf("The embedding downstream analyses should use is %s.", production_label), "")
  if (!is.null(production_embedding)) {
    plotted <- {
      grDevices::png(fig_path("production_geometry.png"), width = 6.5, height = 6, units = "in", res = 120)
      ok <- plot_embedding_geometry(production_embedding, item_colors,
                                     sprintf("Production embedding (d=%d)", ncol(production_embedding)))
      grDevices::dev.off()
      ok
    }
    if (isTRUE(plotted)) {
      md <- c(md, paste0("![Production embedding geometry](", fig_rel("production_geometry.png"), ")"), "")
    } else {
      unlink(fig_path("production_geometry.png"))
      md <- c(md, sprintf("No generic geometry plot is defined for d = %d.", ncol(production_embedding)), "")
    }
  } else {
    md <- c(md, "No production embedding found in `output_dir` (an incomplete run?).", "")
  }

  writeLines(md, output_md)
  if (verbose) cat("Wrote", output_md, "\n")
  invisible(run)
}
