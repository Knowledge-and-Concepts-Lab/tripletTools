test_that("wilson_ci stays within [0,1] and matches a hand-computed value", {
  ci <- wilson_ci(x = 0, n = 10)
  expect_true(ci$lower >= 0 && ci$lower <= ci$upper && ci$upper <= 1)
  expect_equal(ci$lower, 0)

  # 95% Wilson interval for 8/10, hand-computed from the closed form.
  z <- stats::qnorm(0.975)
  phat <- 0.8; n <- 10
  denom <- 1 + z^2 / n
  center <- (phat + z^2 / (2 * n)) / denom
  halfwidth <- (z * sqrt(phat * (1 - phat) / n + z^2 / (4 * n^2))) / denom
  expected <- c(center - halfwidth, center + halfwidth)

  ci2 <- wilson_ci(8, 10)
  expect_equal(c(ci2$lower, ci2$upper), expected)
})

test_that("bin_accuracy_by_strength produces one row per requested bin, with correct n/p_correct", {
  strength <- rep(seq(0.5, 1, length.out = 10), each = 10)
  accuracy <- as.numeric(strength > 0.7)

  bins <- bin_accuracy_by_strength(strength, accuracy, n_bins = 5, binning = "quantile", verbose = FALSE)

  expect_equal(nrow(bins), 5)
  expect_equal(sum(bins$n), length(strength))
  expect_true(all(bins$p_correct %in% c(0, 1))) # deterministic accuracy by construction
})

test_that("bin_accuracy_by_strength collapses bins and messages when strength has heavy ties", {
  strength <- c(rep(1, 50), seq(0.5, 0.9, length.out = 10))
  accuracy <- rbinom(length(strength), 1, 0.7)

  expect_message(
    bins <- bin_accuracy_by_strength(strength, accuracy, n_bins = 10, binning = "quantile", verbose = TRUE),
    "collapsed this to"
  )
  expect_lt(nrow(bins), 10)
})

test_that("plot_accuracy_vs_strength runs end to end and returns bins + a fitted glm", {
  pdf(NULL) # null graphics device, no file written
  on.exit(dev.off())

  set.seed(1)
  n <- 100
  strength <- runif(n, 0.5, 1)
  accuracy <- rbinom(n, 1, strength)

  out <- plot_accuracy_vs_strength(strength, accuracy, n_bins = 5)

  expect_true(all(c("strength", "n", "n_correct", "p_correct", "ci_lower", "ci_upper") %in% names(out$bins)))
  expect_s3_class(out$glm_fit, "glm")
  expect_equal(sum(out$bins$n), n)
})

test_that("plot_accuracy_vs_strength respects glm = FALSE and show_raw = FALSE", {
  pdf(NULL)
  on.exit(dev.off())

  set.seed(1)
  strength <- runif(50, 0.5, 1)
  accuracy <- rbinom(50, 1, strength)

  out <- plot_accuracy_vs_strength(strength, accuracy, glm = FALSE, show_raw = FALSE)
  expect_null(out$glm_fit)
})

test_that("plot_accuracy_vs_strength errors on mismatched lengths and non-binary accuracy", {
  expect_error(plot_accuracy_vs_strength(1:5, 1:4), "same length")
  expect_error(plot_accuracy_vs_strength(c(0.5, 0.6), c(0, 2)), "0/1")
})

test_that("plot_accuracy_vs_strength drops NAs with a message", {
  pdf(NULL)
  on.exit(dev.off())

  strength <- c(0.5, 0.6, NA, 0.8)
  accuracy <- c(1, 0, 1, NA)
  expect_message(
    out <- plot_accuracy_vs_strength(strength, accuracy, n_bins = 2),
    "Dropping 2"
  )
  expect_equal(sum(out$bins$n), 2)
})
