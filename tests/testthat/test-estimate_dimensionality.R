skip_if_not_installed("reticulate")
skip_if(
  inherits(tryCatch(.get_compute_py(), error = function(e) e), "error"),
  "Python embedding backend not available"
)

trips <- make_fake_triplet_list()

# Dimension/restart/epoch counts here are chosen to be as small as possible
# while still exercising the real grid-search loop -- this test checks that
# the pipeline runs and returns the right shapes, not that it converges.

test_that("estimate_dimensionality runs and returns accuracy/norm_ratio columns", {
  dim_est <- estimate_dimensionality(
    triplet_list = trips, dims = 1:2, n_restarts = 2L,
    max_epochs = 20L, tol_window = 10L, seed = 1L, verbose = FALSE
  )

  expect_true(all(
    c("d", "restart", "loss", "accuracy", "epoch", "norm_ratio") %in%
      names(dim_est$results)
  ))
  expect_equal(nrow(dim_est$results), 4L)  # 2 dims x 2 restarts
  expect_true(all(dim_est$results$norm_ratio >= 1 - 1e-8))
  expect_true(all(dim_est$results$accuracy >= 0 & dim_est$results$accuracy <= 1))

  expect_true(all(
    c("d", "mean_loss", "min_loss", "sd_loss", "mean_accuracy", "sd_accuracy",
      "mean_norm_ratio", "max_norm_ratio", "penalized_loss", "best_d") %in%
      names(dim_est$summary)
  ))
  expect_equal(nrow(dim_est$summary), 2L)
  expect_true(sum(dim_est$summary$best_d) == 1L)

  # mean_accuracy in summary must match the per-restart accuracy values
  expect_equal(
    dim_est$summary$mean_accuracy,
    vapply(split(dim_est$results$accuracy, dim_est$results$d), mean, numeric(1),
           USE.NAMES = FALSE)
  )

  # norm_penalty/best_d_norm_penalty default to 0, so penalized_loss must
  # equal mean_loss and best_d selection must be unaffected by norm_ratio.
  expect_equal(dim_est$summary$penalized_loss, dim_est$summary$mean_loss)
})

test_that("best_d_norm_penalty shifts penalized_loss and can change best_d", {
  dim_est <- estimate_dimensionality(
    triplet_list = trips, dims = 1:2, n_restarts = 2L,
    max_epochs = 20L, tol_window = 10L, seed = 1L, verbose = FALSE,
    best_d_norm_penalty = 10
  )

  expected <- dim_est$summary$mean_loss +
    10 * (dim_est$summary$max_norm_ratio - 1)
  expect_equal(dim_est$summary$penalized_loss, expected)

  # Raw loss columns must stay untouched by the penalty.
  expect_equal(
    dim_est$summary$mean_loss,
    vapply(split(dim_est$results$loss, dim_est$results$d), mean, numeric(1),
           USE.NAMES = FALSE)
  )
})

test_that("norm_penalty = 0 preserves per-fit checkpoint-selection behavior", {
  dim_est_default <- estimate_dimensionality(
    triplet_list = trips, dims = 1:2, n_restarts = 2L,
    max_epochs = 20L, tol_window = 10L, seed = 1L, verbose = FALSE
  )
  dim_est_explicit_zero <- estimate_dimensionality(
    triplet_list = trips, dims = 1:2, n_restarts = 2L,
    max_epochs = 20L, tol_window = 10L, seed = 1L, verbose = FALSE,
    norm_penalty = 0
  )

  expect_equal(dim_est_default$results, dim_est_explicit_zero$results)
  expect_equal(dim_est_default$summary, dim_est_explicit_zero$summary)
})

test_that("norm_penalty is accepted and forwarded without error", {
  dim_est <- estimate_dimensionality(
    triplet_list = trips, dims = 1:2, n_restarts = 2L,
    max_epochs = 20L, tol_window = 10L, seed = 1L, verbose = FALSE,
    norm_penalty = 5
  )
  expect_equal(nrow(dim_est$results), 4L)
})
