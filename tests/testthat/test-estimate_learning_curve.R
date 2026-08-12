skip_if_not_installed("reticulate")
skip_if(
  inherits(tryCatch(.get_compute_py(), error = function(e) e), "error"),
  "Python embedding backend not available"
)

trips <- make_fake_triplet_list()

# Fraction/restart/epoch counts here are chosen to be as small as possible
# while still exercising the real grid-search loop -- this test checks that
# the pipeline runs and returns the right shapes, not that it converges.

test_that("estimate_learning_curve runs and returns norm_ratio columns", {
  curve <- estimate_learning_curve(
    triplet_list = trips, d = 2L, by = 0.5, n_restarts = 2L,
    max_epochs = 20L, tol_window = 10L, seed = 1L, verbose = FALSE
  )

  expect_true(all(
    c("fraction", "n_train", "restart", "loss", "accuracy", "epoch",
      "norm_ratio", "n_internal_test") %in% names(curve$results)
  ))
  expect_equal(nrow(curve$results), 4L)  # 2 fractions x 2 restarts
  expect_true(all(curve$results$norm_ratio >= 1 - 1e-8))
  expect_true(all(curve$results$n_internal_test > 0))

  # A given restart's internal_test sample is drawn independently of
  # fraction, so it must be identical in size across every fraction for
  # that restart (apples-to-apples fraction comparisons within a restart --
  # see the "Sampling scheme" section of ?estimate_learning_curve).
  by_restart <- split(curve$results$n_internal_test, curve$results$restart)
  for (sizes in by_restart) expect_equal(length(unique(sizes)), 1L)

  expect_true(all(
    c("fraction", "n_train", "mean_loss", "sd_loss", "mean_accuracy",
      "sd_accuracy", "mean_norm_ratio", "max_norm_ratio") %in% names(curve$summary)
  ))
  expect_equal(nrow(curve$summary), 2L)
})

test_that("internal_test_frac controls the internal_test split size", {
  curve <- estimate_learning_curve(
    triplet_list = trips, d = 2L, by = 0.5, n_restarts = 2L,
    max_epochs = 20L, tol_window = 10L, seed = 1L, verbose = FALSE,
    internal_test_frac = 0.3
  )
  n_train_pool <- sum(vapply(trips, function(df) sum(df$sampleSet == "train"), integer(1)))
  expect_true(all(curve$results$n_internal_test == floor(0.3 * n_train_pool)))

  # n_train (rows actually fit on) must never exceed the fit pool left
  # after carving out internal_test.
  expect_true(all(curve$results$n_train <= n_train_pool - floor(0.3 * n_train_pool)))
})

test_that("norm_penalty = 0 preserves checkpoint-selection behavior, nonzero doesn't error", {
  curve_default <- estimate_learning_curve(
    triplet_list = trips, d = 2L, by = 0.5, n_restarts = 2L,
    max_epochs = 20L, tol_window = 10L, seed = 1L, verbose = FALSE
  )
  curve_explicit_zero <- estimate_learning_curve(
    triplet_list = trips, d = 2L, by = 0.5, n_restarts = 2L,
    max_epochs = 20L, tol_window = 10L, seed = 1L, verbose = FALSE,
    norm_penalty = 0
  )
  expect_equal(curve_default$results, curve_explicit_zero$results)
  expect_equal(curve_default$summary, curve_explicit_zero$summary)

  curve_penalized <- estimate_learning_curve(
    triplet_list = trips, d = 2L, by = 0.5, n_restarts = 2L,
    max_epochs = 20L, tol_window = 10L, seed = 1L, verbose = FALSE,
    norm_penalty = 5
  )
  expect_equal(nrow(curve_penalized$results), 4L)
})
