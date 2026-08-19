test_that("repeated_stratified_logistic_cv() runs and returns expected structure", {
  set.seed(1)
  n <- 40
  X <- rbind(
    cbind(rnorm(n / 2, mean = -2), rnorm(n / 2)),
    cbind(rnorm(n / 2, mean =  2), rnorm(n / 2))
  )
  y <- rep(c(0, 1), each = n / 2)

  cv_result <- repeated_stratified_logistic_cv(
    X = X, y = y,
    repetitions = 5, folds = 3, seed = 1
  )

  expect_s3_class(cv_result, "repetitioned_logistic_cv")
  expect_true(all(c("performance", "summary", "diagnostics", "predictions",
                     "settings") %in% names(cv_result)))
  expect_equal(nrow(cv_result$performance), 5L)
  expect_equal(nrow(cv_result$diagnostics), 5L * 3L)
  expect_equal(nrow(cv_result$predictions), 5L * n)
  expect_true(all(c("mean", "sd", "median", "lower_2.5", "upper_97.5") %in%
                    names(cv_result$summary)))

  # Well-separated clusters should be predicted with high accuracy
  mean_accuracy <- cv_result$summary$mean[cv_result$summary$metric == "accuracy"]
  expect_gt(mean_accuracy, 0.9)
})

test_that("repeated_stratified_logistic_cv() accepts logical and factor outcomes", {
  set.seed(1)
  n <- 30
  X <- rbind(
    cbind(rnorm(n / 2, mean = -2)),
    cbind(rnorm(n / 2, mean =  2))
  )
  y_logical <- rep(c(FALSE, TRUE), each = n / 2)
  y_factor  <- factor(rep(c("no", "yes"), each = n / 2))

  cv_logical <- repeated_stratified_logistic_cv(X, y_logical, repetitions = 2, folds = 2, seed = 1)
  cv_factor  <- suppressMessages(
    repeated_stratified_logistic_cv(X, y_factor, repetitions = 2, folds = 2, seed = 1)
  )

  expect_equal(nrow(cv_logical$predictions), 2L * n)
  expect_equal(nrow(cv_factor$predictions), 2L * n)
})

test_that("repeated_stratified_logistic_cv() validates its inputs", {
  X <- matrix(rnorm(20), nrow = 10)
  y <- rep(c(0, 1), each = 5)

  expect_error(
    repeated_stratified_logistic_cv(X, y[-1], repetitions = 1, folds = 2),
    "number of rows"
  )
  expect_error(
    repeated_stratified_logistic_cv(X, y, repetitions = 1, folds = 1),
    "folds must be at least 2"
  )
  expect_error(
    repeated_stratified_logistic_cv(X, y, repetitions = 1, folds = 10),
    "at least as many observations"
  )
})
