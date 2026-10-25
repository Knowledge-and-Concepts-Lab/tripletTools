## Builds a small, self-contained fake condor_joint_manifold_workflow.py
## output directory (same structure as a real one, see read_joint_manifold_run())
## so summarize_joint_estimation() can be tested without a real Condor run.
build_fake_jm_output <- function(tmp, n_outer = 10, d = 2, oscillate_last = TRUE,
                                  oscillate_alpha_last = FALSE) {
  set.seed(42)  # the per-person jitter below is random; keep the fixture deterministic
  items <- c("a", "b", "c", "d")
  workers <- as.character(1:6)
  dir.create(file.path(tmp, "setup", "original_embeddings"), recursive = TRUE)
  writeLines(workers, file.path(tmp, "setup", "worker_ids.txt"))
  writeLines(items, file.path(tmp, "setup", "item_order.txt"))

  base_emb <- if (d == 2) {
    matrix(c(0, 0, 1, 0, 1, 1, 0, 1), 4, 2, byrow = TRUE)
  } else {
    matrix(c(0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 1), 4, 3, byrow = TRUE)
  }
  dimnames(base_emb) <- list(items, paste0("dim_", seq_len(d) - 1))

  write_emb <- function(path, mat, jitter = 0) {
    out <- as.data.frame(mat + jitter * stats::rnorm(length(mat)))
    out <- cbind(item = rownames(mat), out)
    utils::write.csv(out, path, row.names = FALSE)
  }

  for (i in seq_along(workers)) {
    write_emb(file.path(tmp, "setup", "original_embeddings", sprintf("person%d.csv", i - 1)),
               base_emb, jitter = 0.05)
  }

  ## Per-iteration positions: everyone converges geometrically toward
  ## final_positions (negligible change by the last few iterations);
  ## participant 1 ("worker 1") then gets a large last-iteration jump away
  ## from its own converged value if oscillate_last is TRUE. Alpha
  ## converges the same way, independently, for participant 2 ("worker 2")
  ## if oscillate_alpha_last is TRUE -- position and alpha are decoupled
  ## now, so each needs its own convergence case.
  final_positions <- seq(-1, 1, length.out = length(workers))
  start_positions <- final_positions * 3
  # Varies across workers (not constant) so downstream paired t-tests on
  # per-worker differences aren't degenerate (zero-variance) when every
  # worker also shares the same toy embedding/trial pattern.
  final_alpha <- seq(1.2, 1.8, length.out = length(workers))
  start_alpha <- final_alpha * 3
  decay <- 0.4
  for (i in seq_len(n_outer)) {
    dir.create(file.path(tmp, paste0("iter", i)), recursive = TRUE, showWarnings = FALSE)
    pos <- final_positions + (start_positions - final_positions) * decay^i
    if (oscillate_last && i == n_outer) {
      pos[1] <- -pos[1] * 2  # big jump away from where it had converged
    }
    utils::write.csv(data.frame(position = pos), file.path(tmp, paste0("iter", i), "positions.csv"),
                      row.names = FALSE)

    alpha_i <- final_alpha + (start_alpha - final_alpha) * decay^i
    if (oscillate_alpha_last && i == n_outer) {
      alpha_i[2] <- alpha_i[2] * 20  # big jump away from where it had converged
    }
    utils::write.csv(data.frame(log_alpha = log(alpha_i), alpha = alpha_i,
                                 tau2 = 0.2, pop_mean_alpha = mean(alpha_i), bandwidth = 0.3),
                      file.path(tmp, paste0("iter", i), "alpha.csv"), row.names = FALSE)

    aligned_dir <- file.path(tmp, paste0("iter", i), "aligned")
    dir.create(aligned_dir, recursive = TRUE, showWarnings = FALSE)
    for (j in seq_along(workers)) {
      out <- as.data.frame(base_emb)
      utils::write.csv(out, file.path(aligned_dir, sprintf("person%d.csv", j - 1)), row.names = FALSE)
    }
  }

  ## final_embeddings.csv / final_positions.csv / final_alpha.csv (as the
  ## real orchestrator writes them)
  final_emb_rows <- do.call(rbind, lapply(seq_along(workers), function(j) {
    data.frame(worker_id = workers[j], item = items, base_emb, row.names = NULL)
  }))
  utils::write.csv(final_emb_rows, file.path(tmp, "final_embeddings.csv"), row.names = FALSE)
  utils::write.csv(data.frame(worker_id = workers, position = final_positions),
                    file.path(tmp, "final_positions.csv"), row.names = FALSE)
  final_alpha_out <- final_alpha
  if (oscillate_alpha_last) final_alpha_out[2] <- final_alpha_out[2] * 20
  utils::write.csv(data.frame(worker_id = workers, alpha = final_alpha_out),
                    file.path(tmp, "final_alpha.csv"), row.names = FALSE)

  writeLines(c(
    "Run finished:    2026-01-01T00:00:00Z",
    "triplet_data:    fake.csv",
    "embeddings:      fake_emb.csv",
    "config:          fake.yml",
    paste0("n_participants:  ", length(workers)),
    paste0("d:               ", d),
    paste0("n_outer:         ", n_outer),
    "mode:            fit",
    "alpha estimation: decoupled (per-person, shrinkage-regularized)",
    "final mean alpha: 1.5",
    "container_image: fake"
  ), file.path(tmp, "run_manifest.txt"))

  workers
}

build_fake_jm_triplet_data <- function(workers) {
  rows <- do.call(rbind, lapply(workers, function(w) {
    rbind(
      data.frame(worker_id = as.integer(w), Center = "a", Left = "b", Right = "c", Answer = "b",
                 sampleAlg = "random", sampleSet = "train", stringsAsFactors = FALSE)[rep(1, 4), ],
      data.frame(worker_id = as.integer(w), Center = "a", Left = "c", Right = "d", Answer = "d",
                 sampleAlg = "validation", sampleSet = NA, stringsAsFactors = FALSE)[rep(1, 4), ]
    )
  }))
  rownames(rows) <- NULL
  rows
}

test_that("summarize_joint_estimation reads convergence diagnostics and flags the oscillating participant", {
  tmp <- tempfile("jm_test_")
  dir.create(tmp)
  workers <- build_fake_jm_output(tmp, oscillate_last = TRUE)

  res <- suppressWarnings(summarize_joint_estimation(tmp, triplet_data = NULL, verbose = FALSE))

  expect_true(file.exists(file.path(tmp, "summary.md")))
  expect_equal(nrow(res$position_flags), length(workers))
  expect_true(res$position_flags$flagged[res$position_flags$worker_id == "1"])
  expect_false(any(res$position_flags$flagged[res$position_flags$worker_id != "1"]))
  expect_false(any(res$alpha_flags$flagged))  # alpha wasn't made to oscillate in this fixture
  expect_null(res$decomposition)
  expect_null(res$loo)
})

test_that("summarize_joint_estimation flags an oscillating alpha trajectory independently of position", {
  tmp <- tempfile("jm_test_")
  dir.create(tmp)
  workers <- build_fake_jm_output(tmp, oscillate_last = FALSE, oscillate_alpha_last = TRUE)

  res <- suppressWarnings(summarize_joint_estimation(tmp, triplet_data = NULL, verbose = FALSE))

  expect_false(any(res$position_flags$flagged))  # position wasn't made to oscillate here
  expect_true(res$alpha_flags$flagged[res$alpha_flags$worker_id == "2"])
  expect_false(any(res$alpha_flags$flagged[res$alpha_flags$worker_id != "2"]))

  md <- readLines(file.path(tmp, "summary.md"))
  expect_true(any(grepl("alpha estimates had not stabilized", md)))
})

test_that("summarize_joint_estimation does not flag a run with no oscillation", {
  tmp <- tempfile("jm_test_")
  dir.create(tmp)
  build_fake_jm_output(tmp, oscillate_last = FALSE)

  res <- suppressWarnings(summarize_joint_estimation(tmp, triplet_data = NULL, verbose = FALSE))
  expect_false(any(res$position_flags$flagged))
})

test_that("summarize_joint_estimation runs the held-out comparison and LOO check when triplet_data is supplied", {
  tmp <- tempfile("jm_test_")
  dir.create(tmp)
  workers <- build_fake_jm_output(tmp, oscillate_last = FALSE)
  trip_data <- build_fake_jm_triplet_data(workers)

  res <- suppressWarnings(summarize_joint_estimation(tmp, triplet_data = trip_data, verbose = FALSE))

  expect_s3_class(res$decomposition, "data.frame")
  expect_equal(nrow(res$decomposition), 7)
  expect_true(any(grepl("grand mean", res$decomposition$comparison)))
  expect_true(all(c("n_win_ll", "mean_diff_ll", "t_ll", "p_ll", "n_win_acc", "p_acc") %in% names(res$decomposition)))
  expect_false(is.null(res$loo))
  expect_equal(nrow(res$loo$accuracy), length(workers))

  md <- readLines(file.path(tmp, "summary.md"))
  expect_true(any(grepl("Held-out validation comparison", md)))
  expect_true(any(grepl("Fully out-of-sample confirmation", md)))
  expect_true(file.exists(file.path(tmp, "summary_files", "comparison_scatter.png")))
  expect_true(file.exists(file.path(tmp, "summary_files", "loo_crossover.png")))
})

test_that("grand mean condition is read from final_grand_mean_embedding.csv when present", {
  tmp <- tempfile("jm_test_")
  dir.create(tmp)
  workers <- build_fake_jm_output(tmp, oscillate_last = FALSE)
  trip_data <- build_fake_jm_triplet_data(workers)

  # Write an explicit (deliberately different-looking) grand-mean file and
  # confirm it's actually read rather than silently recomputed.
  gm <- data.frame(item = c("a", "b", "c", "d"),
                    dim_0 = c(0, 5, 5, 0), dim_1 = c(0, 0, 5, 5))
  utils::write.csv(gm, file.path(tmp, "final_grand_mean_embedding.csv"), row.names = FALSE)

  run <- read_joint_manifold_run(tmp)
  expect_false(is.null(run$final_grand_mean_embedding))
  expect_equal(unname(run$final_grand_mean_embedding["b", "dim_0"]), 5)
})

test_that("summarize_joint_estimation skips the comparison sections cleanly with no triplet_data", {
  tmp <- tempfile("jm_test_")
  dir.create(tmp)
  build_fake_jm_output(tmp, oscillate_last = FALSE)

  res <- suppressWarnings(summarize_joint_estimation(tmp, triplet_data = NULL, verbose = FALSE))
  md <- readLines(file.path(tmp, "summary.md"))
  expect_true(any(grepl("Skipped: no .triplet_data. supplied", md)))
})

test_that("summarize_joint_estimation handles d = 3 via the scatterplot3d geometry grid", {
  skip_if_not_installed("scatterplot3d")
  tmp <- tempfile("jm_test_")
  dir.create(tmp)
  build_fake_jm_output(tmp, d = 3, oscillate_last = FALSE)

  res <- suppressWarnings(summarize_joint_estimation(tmp, triplet_data = NULL, verbose = FALSE))
  expect_true(file.exists(file.path(tmp, "summary_files", "geometry_grid.png")))
})

test_that("summarize_joint_estimation errors clearly on a non-workflow directory", {
  tmp <- tempfile("jm_test_")
  dir.create(tmp)
  expect_error(summarize_joint_estimation(tmp, verbose = FALSE), "run_manifest.txt")
})

test_that("flag_unstable_joint_positions flags only participants with a large recent range", {
  pos <- rbind(
    stable   = c(0, 0.01, 0.01, 0.01, 0.01),
    unstable = c(0, 0.5, -0.5, 0.5, -0.5)
  )
  flags <- flag_unstable_joint_positions(pos, window = 4, threshold_frac = 0.1)
  expect_false(flags$flagged[flags$worker_id == "stable"])
  expect_true(flags$flagged[flags$worker_id == "unstable"])
})

test_that("flag_unstable_joint_alpha flags only participants with a large recent log-alpha range", {
  alpha <- rbind(
    stable   = c(1.5, 1.51, 1.49, 1.50, 1.50),
    unstable = c(1.5, 30, 1.5, 30, 12)
  )
  flags <- flag_unstable_joint_alpha(alpha, window = 4, threshold_frac = 0.1)
  expect_false(flags$flagged[flags$worker_id == "stable"])
  expect_true(flags$flagged[flags$worker_id == "unstable"])
})

test_that("estimate_shrunk_alpha shrinks a noisy individual estimate toward the population", {
  items <- c("a", "b", "c", "d")
  base_emb <- matrix(c(0, 0, 1, 0, 1, 1, 0, 1), 4, 2, byrow = TRUE,
                      dimnames = list(items, c("dim_0", "dim_1")))
  embeddings <- list(w1 = base_emb, w2 = base_emb, w3 = base_emb)
  # A tiny, uninformative trial set for w3 (one trial only) should pull its
  # shrunk estimate toward the other two, better-identified participants'.
  trials <- list(
    w1 = list(head = rep(c("a", "b"), 10), winner = rep(c("b", "c"), 10), loser = rep(c("d", "a"), 10)),
    w2 = list(head = rep(c("a", "b"), 10), winner = rep(c("b", "c"), 10), loser = rep(c("d", "a"), 10)),
    w3 = list(head = "a", winner = "b", loser = "d")
  )
  shrunk <- estimate_shrunk_alpha(embeddings, trials)
  expect_equal(names(shrunk), c("w1", "w2", "w3"))
  expect_true(all(is.finite(shrunk)) && all(shrunk > 0))
})
