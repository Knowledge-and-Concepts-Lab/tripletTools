# Pure aggregation functions -- test against synthetic results data frames
# directly, no Python backend needed.

test_that("summarize_dimensionality reproduces the expected columns and mean_loss", {
  results <- data.frame(
    d          = rep(1:2, each = 4),
    restart    = rep(1:4, times = 2),
    loss       = c(0.50, 0.52, 0.48, 0.50, 0.30, 0.32, 0.28, 0.30),
    accuracy   = 0.8,
    norm_ratio = 1.2
  )

  summary_df <- summarize_dimensionality(results, n_restarts = 4L)

  expect_equal(summary_df$d, 1:2)
  expect_true(all(c("d", "mean_loss", "min_loss", "sd_loss", "mean_accuracy",
                     "sd_accuracy", "mean_norm_ratio", "max_norm_ratio",
                     "penalized_loss", "best_d") %in% names(summary_df)))
  expect_equal(summary_df$mean_loss, c(0.50, 0.30), tolerance = 1e-8)
  expect_equal(summary_df$min_loss, c(0.48, 0.28), tolerance = 1e-8)
  # best_d_norm_penalty defaults to 0 -> penalized_loss == mean_loss
  expect_equal(summary_df$penalized_loss, summary_df$mean_loss)
})

test_that("summarize_dimensionality's best_d applies the one-SE parsimony rule", {
  # d=3 has the global minimum mean_loss but high variance; d=2's mean_loss
  # falls within d=3's one-SE band, so the smaller, more parsimonious d=2
  # should be selected over d=3.
  results <- data.frame(
    d          = rep(1:3, each = 4),
    restart    = rep(1:4, times = 3),
    loss       = c(0.50, 0.52, 0.48, 0.50,   # d=1: mean 0.50, tight
                   0.30, 0.32, 0.30, 0.32,   # d=2: mean 0.31, tight
                   0.20, 0.40, 0.20, 0.40),  # d=3: mean 0.30, high variance
    accuracy   = 0.8,
    norm_ratio = 1
  )

  summary_df <- summarize_dimensionality(results, n_restarts = 4L)

  expect_equal(summary_df$mean_loss, c(0.50, 0.31, 0.30), tolerance = 1e-8)
  expect_true(summary_df$best_d[summary_df$d == 2])
  expect_false(any(summary_df$best_d[summary_df$d != 2]))
})

test_that("best_d_norm_penalty can flip best_d away from a high-norm_ratio dimension", {
  # Equal-variance (sd = 0) groups so the one-SE rule contributes nothing,
  # isolating the effect of the norm penalty itself.
  results <- data.frame(
    d          = rep(1:2, each = 4),
    restart    = rep(1:4, times = 2),
    loss       = c(0.31, 0.31, 0.31, 0.31,   # d=1: higher loss, low norm_ratio
                   0.30, 0.30, 0.30, 0.30),  # d=2: lower loss, high norm_ratio
    accuracy   = 0.8,
    norm_ratio = c(1, 1, 1, 1,  5, 5, 5, 5)
  )

  unpenalized <- summarize_dimensionality(results, n_restarts = 4L, best_d_norm_penalty = 0)
  expect_true(unpenalized$best_d[unpenalized$d == 2])

  penalized <- summarize_dimensionality(results, n_restarts = 4L, best_d_norm_penalty = 1)
  expect_equal(penalized$penalized_loss, c(0.31, 4.30), tolerance = 1e-8)
  expect_true(penalized$best_d[penalized$d == 1])
  expect_false(penalized$best_d[penalized$d == 2])
})

test_that("summarize_learning_curve reproduces the expected columns and per-fraction stats", {
  results <- data.frame(
    fraction   = rep(c(0.5, 1.0), each = 3),
    n_train    = rep(c(50L, 100L), each = 3),
    restart    = rep(1:3, times = 2),
    loss       = c(0.50, 0.52, 0.48, 0.30, 0.32, 0.28),
    accuracy   = c(0.6, 0.62, 0.58, 0.8, 0.82, 0.78),
    norm_ratio = c(1.1, 1.2, 1.0, 1.3, 1.4, 1.2)
  )

  summary_df <- summarize_learning_curve(results)

  expect_equal(summary_df$fraction, c(0.5, 1.0))
  expect_true(all(c("fraction", "n_train", "mean_loss", "sd_loss", "mean_accuracy",
                     "sd_accuracy", "mean_norm_ratio", "max_norm_ratio") %in%
                    names(summary_df)))
  expect_equal(summary_df$n_train, c(50L, 100L))
  expect_equal(summary_df$mean_loss, c(mean(c(0.50, 0.52, 0.48)), mean(c(0.30, 0.32, 0.28))))
  expect_equal(summary_df$max_norm_ratio, c(1.2, 1.4))
})
