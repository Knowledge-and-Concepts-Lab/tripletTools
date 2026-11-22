## Builds a small, self-contained fake condor_workflow.py output directory
## (same file shapes as a real one -- see read_group_embedding_run()) so
## summarize_group_embedding_run() can be tested without a real Condor run.
build_fake_condor_workflow_output <- function(tmp, d = 2, ran_learning_curve = TRUE,
                                               ran_alpha_stages = TRUE,
                                               n_restarts_dim = 3, n_restarts_final = 1) {
  set.seed(1)
  n_items <- 6
  items <- sprintf("i%02d", seq_len(n_items))

  write_embedding <- function(path, d_this) {
    mat <- matrix(stats::rnorm(n_items * d_this), n_items, d_this)
    colnames(mat) <- paste0("dim_", seq_len(d_this) - 1)
    out <- cbind(item = items, as.data.frame(mat))
    utils::write.csv(out, path, row.names = FALSE)
  }

  write_history <- function(path, start_loss = 0.69, end_loss = 0.35, n_epoch = 5) {
    epoch <- seq(0, by = 100, length.out = n_epoch)
    loss <- seq(start_loss, end_loss, length.out = n_epoch)
    utils::write.csv(data.frame(
      epoch = epoch, train_loss = loss - 0.01, test_loss = loss,
      train_acc = seq(0.5, 0.85, length.out = n_epoch),
      test_acc = seq(0.5, 0.83, length.out = n_epoch),
      max_norm = 1, median_norm = 0.5, norm_ratio = 2
    ), path, row.names = FALSE)
  }

  ## Stage 1
  dims <- 1:4
  dim_rows <- do.call(rbind, lapply(dims, function(dd) {
    data.frame(d = dd, restart = seq_len(n_restarts_dim),
               loss = 0.4 - 0.01 * dd + stats::rnorm(n_restarts_dim, sd = 0.001),
               accuracy = 0.8, epoch = 500, norm_ratio = 2,
               n_fit = 100, n_internal_test = 20)
  }))
  utils::write.csv(dim_rows, file.path(tmp, "dimensionality_results.csv"), row.names = FALSE)
  dim_summary <- do.call(rbind, lapply(dims, function(dd) {
    sub <- dim_rows[dim_rows$d == dd, ]
    data.frame(d = dd, mean_loss = mean(sub$loss), min_loss = min(sub$loss),
               sd_loss = stats::sd(sub$loss), mean_accuracy = mean(sub$accuracy),
               sd_accuracy = stats::sd(sub$accuracy), mean_norm_ratio = 2, max_norm_ratio = 2.5,
               penalized_loss = mean(sub$loss), best_d = (dd == d))
  }))
  utils::write.csv(dim_summary, file.path(tmp, "dimensionality_summary.csv"), row.names = FALSE)

  ## Stage 2 (optional)
  if (ran_learning_curve) {
    fractions <- seq(0.2, 1, by = 0.2)
    lc_rows <- do.call(rbind, lapply(fractions, function(f) {
      data.frame(fraction = f, n_train = round(f * 100), restart = 1:3,
                 loss = 0.6 - 0.2 * f + stats::rnorm(3, sd = 0.01),
                 accuracy = 0.5 + 0.3 * f + stats::rnorm(3, sd = 0.01),
                 epoch = 500, norm_ratio = 2, n_internal_test = 20)
    }))
    utils::write.csv(lc_rows, file.path(tmp, "learning_curve_results.csv"), row.names = FALSE)
    lc_summary <- do.call(rbind, lapply(fractions, function(f) {
      sub <- lc_rows[lc_rows$fraction == f, ]
      data.frame(fraction = f, n_train = sub$n_train[1], mean_loss = mean(sub$loss),
                 sd_loss = stats::sd(sub$loss), mean_accuracy = mean(sub$accuracy),
                 sd_accuracy = stats::sd(sub$accuracy), mean_norm_ratio = 2, max_norm_ratio = 2.5)
    }))
    utils::write.csv(lc_summary, file.path(tmp, "learning_curve_summary.csv"), row.names = FALSE)
  }

  ## Stage 3
  write_embedding(file.path(tmp, "best_embedding.csv"), d)
  write_history(file.path(tmp, "best_embedding_history.csv"))
  utils::write.csv(data.frame(restart = 1, seed = 1, loss = 0.35),
                    file.path(tmp, "best_embedding_restarts.csv"), row.names = FALSE)

  alpha <- NA_real_
  if (ran_alpha_stages) {
    ## Stage 4
    alpha <- 3.5
    utils::write.csv(data.frame(iter = 1:3, alpha = c(1.5, 2.8, alpha),
                                 ll_alpha_test = c(-100, -95, -94),
                                 acc_alpha_test = c(0.8, 0.82, 0.83),
                                 epoch = c(400, 350, 300),
                                 delta_log_alpha = c(0.6, 0.2, 0.03)),
                      file.path(tmp, "alpha_history.csv"), row.names = FALSE)
    utils::write.csv(data.frame(alpha = alpha, log_alpha = log(alpha), ci_lo = alpha,
                                 ci_hi = alpha * 1.2, n_test_fit = 50, n_alpha_test = 70),
                      file.path(tmp, "alpha_result.csv"), row.names = FALSE)
    write_embedding(file.path(tmp, "alpha_embedding.csv"), d)

    ## Stage 5
    write_embedding(file.path(tmp, "best_final_embedding.csv"), d)
    write_history(file.path(tmp, "best_final_embedding_history.csv"))
    final_restarts <- data.frame(restart = seq_len(n_restarts_final),
                                  seed = seq_len(n_restarts_final),
                                  loss = 0.30 + stats::rnorm(n_restarts_final, sd = 0.0001))
    utils::write.csv(final_restarts, file.path(tmp, "best_final_embedding_restarts.csv"), row.names = FALSE)
  }

  writeLines(c(
    "Run finished:   2026-01-01T00:00:00Z",
    "triplet_data:   fake.csv",
    "config:         fake.yml",
    "geometry:       euclidean",
    "norm_penalty:   0",
    paste0("learning_curve: ", if (ran_learning_curve) "ran" else "skipped (run_learning_curve: false)"),
    paste0("best_d:         ", d),
    paste0("alpha:          ", if (ran_alpha_stages) alpha else "N/A (refit_alpha: false)"),
    "container_image:fake"
  ), file.path(tmp, "run_manifest.txt"))

  invisible(NULL)
}

test_that("summarize_group_embedding_run writes a complete report when every stage ran", {
  tmp <- tempfile("cw_test_")
  dir.create(tmp)
  build_fake_condor_workflow_output(tmp, d = 2, n_restarts_final = 5)

  res <- summarize_group_embedding_run(tmp, verbose = FALSE)

  expect_true(file.exists(file.path(tmp, "summary.md")))
  md <- readLines(file.path(tmp, "summary.md"))
  expect_true(any(grepl("best_d = 2", md, fixed = TRUE)))
  expect_true(any(grepl("This is the production embedding", md, fixed = TRUE)))
  expect_false(any(grepl("^Skipped", md)))

  fig_dir <- file.path(tmp, "summary_files")
  expect_true(file.exists(file.path(fig_dir, "dimensionality.png")))
  expect_true(file.exists(file.path(fig_dir, "learning_curve.png")))
  expect_true(file.exists(file.path(fig_dir, "stage3_history.png")))
  expect_true(file.exists(file.path(fig_dir, "alpha_history.png")))
  expect_true(file.exists(file.path(fig_dir, "stage5_history.png")))
  expect_true(file.exists(file.path(fig_dir, "stage5_restarts.png")))
  expect_true(file.exists(file.path(fig_dir, "production_geometry.png")))
  # Only one restart at stage 3 -- the restarts plot should be skipped
  expect_false(file.exists(file.path(fig_dir, "stage3_restarts.png")))

  expect_equal(res$best_d, 2L)
  expect_equal(res$alpha, 3.5)
})

test_that("summarize_group_embedding_run notes skipped stages 2/4/5 and uses the warm-start embedding as production", {
  tmp <- tempfile("cw_test_")
  dir.create(tmp)
  build_fake_condor_workflow_output(tmp, d = 2, ran_learning_curve = FALSE, ran_alpha_stages = FALSE)

  res <- summarize_group_embedding_run(tmp, verbose = FALSE)
  md <- readLines(file.path(tmp, "summary.md"))

  expect_true(any(grepl("Skipped \\(`run_learning_curve: false`", md)))
  expect_true(any(grepl("Skipped \\(`refit_alpha: false`", md)))
  expect_true(any(grepl("best_embedding.csv.*Stage 3", md)))
  expect_true(any(grepl("this is the production embedding", md, ignore.case = TRUE)))

  fig_dir <- file.path(tmp, "summary_files")
  expect_false(file.exists(file.path(fig_dir, "learning_curve.png")))
  expect_false(file.exists(file.path(fig_dir, "alpha_history.png")))
  expect_false(file.exists(file.path(fig_dir, "stage5_history.png")))
  expect_true(file.exists(file.path(fig_dir, "production_geometry.png")))

  expect_true(is.na(res$alpha))
  expect_null(res$final_embedding)
})

test_that("summarize_group_embedding_run handles d = 1 (a real, not hypothetical, best_d) and colors every item", {
  tmp <- tempfile("cw_test_")
  dir.create(tmp)
  build_fake_condor_workflow_output(tmp, d = 1)

  expect_no_error(summarize_group_embedding_run(tmp, verbose = FALSE))
  expect_true(file.exists(file.path(tmp, "summary_files", "production_geometry.png")))
})

test_that("summarize_group_embedding_run errors clearly when run_manifest.txt is missing", {
  tmp <- tempfile("cw_test_")
  dir.create(tmp)
  expect_error(summarize_group_embedding_run(tmp, verbose = FALSE), "run_manifest.txt")
})

test_that("plot_embedding_geometry (d = 1) colors every item individually, not just the first", {
  # Regression test for a real bug: graphics::stripchart() silently honors
  # only col[1] for an ungrouped vector of points -- confirmed directly by
  # rendering a test plot -- which would have made every item the same
  # color in the d = 1 case. Checked by rendering to a real PNG and
  # counting distinct non-background colors, rather than reaching into
  # plot-object internals.
  emb <- matrix(seq(-2, 2, length.out = 6), 6, 1, dimnames = list(letters[1:6], "dim_0"))
  colors <- grDevices::rainbow(6)
  tmp_png <- tempfile(fileext = ".png")
  grDevices::png(tmp_png, width = 4, height = 3, units = "in", res = 100)
  plot_embedding_geometry(emb, item_colors = colors, main = "test")
  grDevices::dev.off()

  img <- png::readPNG(tmp_png)
  px <- matrix(img[, , 1:3], ncol = 3)
  is_colored <- !(px[, 1] > 0.95 & px[, 2] > 0.95 & px[, 3] > 0.95) &  # not white background
                !(px[, 1] < 0.05 & px[, 2] < 0.05 & px[, 3] < 0.05)    # not black axis/text
  distinct_colors <- unique(round(px[is_colored, , drop = FALSE], 2))
  expect_gt(nrow(distinct_colors), 1)
})
