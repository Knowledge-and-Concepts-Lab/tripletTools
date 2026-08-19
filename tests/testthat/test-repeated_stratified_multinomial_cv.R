test_that("repeated_stratified_multinomial_cv() runs and returns expected structure", {
  set.seed(1)
  n <- 60
  # Deliberately mild separation -- see the roxygen example for why cleanly
  # separated clusters trip every fold's unstable_fit flag (expected
  # quasi-complete-separation behavior, not something this test is after).
  X <- rbind(
    cbind(rnorm(n / 3, mean = -1.5), rnorm(n / 3)),
    cbind(rnorm(n / 3, mean =  0),   rnorm(n / 3, mean = 1.5)),
    cbind(rnorm(n / 3, mean =  1.5), rnorm(n / 3))
  )
  y <- factor(rep(c("a", "b", "c"), each = n / 3))

  cv_result <- repeated_stratified_multinomial_cv(
    X = X, y = y,
    repetitions = 5, folds = 3, seed = 1
  )

  expect_s3_class(cv_result, "repetitioned_multinomial_cv")
  expect_true(all(c("performance", "summary", "per_class_performance",
                     "per_class_summary", "diagnostics", "predictions",
                     "settings") %in% names(cv_result)))
  expect_equal(nrow(cv_result$performance), 5L)
  expect_equal(nrow(cv_result$diagnostics), 5L * 3L)
  expect_equal(nrow(cv_result$predictions), 5L * n)
  expect_equal(nrow(cv_result$per_class_summary), 3L)
  expect_setequal(cv_result$per_class_summary$class, c("a", "b", "c"))
  expect_true(all(c("mean", "sd", "median", "lower_2.5", "upper_97.5") %in%
                    names(cv_result$summary)))
  expect_setequal(cv_result$summary$metric,
                   c("accuracy", "balanced_accuracy", "precision", "f1", "auc"))

  # Classes are separable enough to beat chance (1/3) comfortably
  mean_accuracy <- cv_result$summary$mean[cv_result$summary$metric == "accuracy"]
  expect_gt(mean_accuracy, 0.6)

  # Predicted class columns include one probability column per level
  expect_true(all(c("a", "b", "c") %in% names(cv_result$predictions)))
})

test_that("unstable_fit correctly fires under near-perfect separation", {
  # Positive control: mirrors the same quasi-complete-separation behavior
  # already present in repeated_stratified_logistic_cv()'s own test data --
  # confirms the diagnostic is doing its job, not that it's a bug.
  set.seed(1)
  n <- 60
  X <- rbind(
    cbind(rnorm(n / 3, mean = -3), rnorm(n / 3)),
    cbind(rnorm(n / 3, mean =  0), rnorm(n / 3, mean = 3)),
    cbind(rnorm(n / 3, mean =  3), rnorm(n / 3))
  )
  y <- factor(rep(c("a", "b", "c"), each = n / 3))

  cv_result <- repeated_stratified_multinomial_cv(X, y, repetitions = 2, folds = 3, seed = 1)
  expect_true(all(cv_result$diagnostics$large_coefficient))
  expect_true(all(cv_result$diagnostics$unstable_fit))
})

test_that("accuracy and AUC are near chance level for unrelated labels", {
  set.seed(2)
  n <- 80
  X <- matrix(rnorm(n * 3), n, 3)
  y <- factor(sample(c("w", "x", "y", "z"), n, replace = TRUE))

  cv_result <- repeated_stratified_multinomial_cv(X, y, repetitions = 5, folds = 4, seed = 2)

  mean_accuracy <- cv_result$summary$mean[cv_result$summary$metric == "accuracy"]
  mean_auc <- cv_result$summary$mean[cv_result$summary$metric == "auc"]
  expect_lt(abs(mean_accuracy - 0.25), 0.15)
  expect_lt(abs(mean_auc - 0.5), 0.15)
})

test_that("repeated_stratified_multinomial_cv() handles the 2-class case", {
  # nnet::multinom's predict(..., type='probs') returns a bare vector (not a
  # matrix) for exactly 2 classes -- this is the case that quirk would break.
  set.seed(3)
  n <- 40
  X <- rbind(cbind(rnorm(n / 2, -3)), cbind(rnorm(n / 2, 3)))
  y <- factor(rep(c("lo", "hi"), each = n / 2))

  cv_result <- repeated_stratified_multinomial_cv(X, y, repetitions = 3, folds = 3, seed = 3)
  expect_equal(nrow(cv_result$per_class_summary), 2L)
  expect_true(all(c("lo", "hi") %in% names(cv_result$predictions)))
  mean_accuracy <- cv_result$summary$mean[cv_result$summary$metric == "accuracy"]
  expect_gt(mean_accuracy, 0.9)
})

test_that("repeated_stratified_multinomial_cv() validates its inputs", {
  X <- matrix(rnorm(30), nrow = 15)
  y <- factor(rep(c("a", "b", "c"), each = 5))

  expect_error(
    repeated_stratified_multinomial_cv(X, factor(rep("a", 15)), repetitions = 1, folds = 2),
    "at least two levels"
  )
  expect_error(
    repeated_stratified_multinomial_cv(X, y[-1], repetitions = 1, folds = 2),
    "number of rows"
  )
  expect_error(
    repeated_stratified_multinomial_cv(X, y, repetitions = 1, folds = 1),
    "folds must be at least 2"
  )
  expect_error(
    repeated_stratified_multinomial_cv(X, y, repetitions = 1, folds = 10),
    "at least as many observations"
  )
})
