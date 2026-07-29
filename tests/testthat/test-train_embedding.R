skip_if_not_installed("reticulate")
skip_if(
  inherits(tryCatch(.get_compute_py(), error = function(e) e), "error"),
  "Python embedding backend not available"
)

set.seed(1)
n_items    <- 5L
n_triplets <- 40L
trip <- t(replicate(n_triplets, sample(0:(n_items - 1L), 3)))
X_train <- trip[1:30, ]
X_test  <- trip[31:40, ]

# Epoch counts here are chosen to be as small as possible while still
# exercising the real training loop -- these tests check that the pipeline
# runs and returns the right shapes, not that it converges.

test_that("train_embedding runs and returns the expected structure", {
  fit <- train_embedding(X_train, X_test, d = 2L, max_epochs = 20L,
                          tol_window = 10L, print_every = 20L, random_state = 0L)

  expect_equal(dim(fit$embedding), c(n_items, 2L))
  expect_true(is.numeric(fit$loss))
  expect_true(is.numeric(fit$epoch))
  expect_s3_class(fit$history, "data.frame")
  expect_true(all(
    c("epoch", "train_loss", "test_loss", "train_acc", "test_acc",
      "max_norm", "median_norm", "norm_ratio") %in% names(fit$history)
  ))
  # norm_ratio = max_norm / median_norm, so it can never fall below 1
  expect_true(all(fit$history$norm_ratio >= 1 - 1e-8))
})

test_that("geometry = 'sphere' constrains points to the sphere's surface", {
  fit <- train_embedding(X_train, X_test, d = 2L, geometry = "sphere", radius = 1,
                          max_epochs = 20L, tol_window = 10L, print_every = 20L,
                          random_state = 0L)

  norms <- sqrt(rowSums(fit$embedding^2))
  expect_equal(norms, rep(1, n_items), tolerance = 1e-4)
  # Every item's norm is pinned to `radius` by construction under
  # geometry = "sphere", so norm_ratio should stay ~1 throughout training.
  expect_equal(fit$history$norm_ratio, rep(1, nrow(fit$history)), tolerance = 1e-4)
})

test_that("warm_start skips the internal Euclidean warm-start stage", {
  fit_e <- train_embedding(X_train, X_test, d = 2L, max_epochs = 20L,
                            tol_window = 10L, print_every = 20L, random_state = 0L)

  out_without <- reticulate::py_capture_output(
    train_embedding(X_train, X_test, d = 2L, geometry = "sphere",
                     max_epochs = 20L, tol_window = 10L, print_every = 20L,
                     random_state = 0L)
  )
  out_with <- reticulate::py_capture_output(
    train_embedding(X_train, X_test, d = 2L, geometry = "sphere",
                     max_epochs = 20L, tol_window = 10L, print_every = 20L,
                     random_state = 0L, warm_start = fit_e$embedding)
  )

  expect_true(grepl("spherical warm start", out_without, fixed = TRUE))
  expect_false(grepl("spherical warm start", out_with, fixed = TRUE))
})

test_that("warm_start with a mismatched shape errors before training", {
  expect_error(
    train_embedding(X_train, X_test, d = 2L, geometry = "sphere",
                     warm_start = matrix(0, 3, 3)),
    "warm_start must have shape"
  )
})

test_that("norm_penalty = 0 preserves checkpoint-selection behavior exactly", {
  fit_default      <- train_embedding(X_train, X_test, d = 2L, max_epochs = 20L,
                                       tol_window = 10L, print_every = 20L,
                                       random_state = 0L)
  fit_explicit_zero <- train_embedding(X_train, X_test, d = 2L, max_epochs = 20L,
                                        tol_window = 10L, print_every = 20L,
                                        random_state = 0L, norm_penalty = 0)

  expect_equal(fit_default$embedding, fit_explicit_zero$embedding)
  expect_equal(fit_default$loss, fit_explicit_zero$loss)
  expect_equal(fit_default$history, fit_explicit_zero$history)
})

test_that("norm_penalty selects the checkpoint with lowest penalized loss", {
  fit <- train_embedding(X_train, X_test, d = 2L, max_epochs = 20L,
                          tol_window = 10L, print_every = 20L, random_state = 0L,
                          norm_penalty = 5)

  # The returned loss must be the raw test_loss of whichever history row
  # minimizes test_loss + norm_penalty * (norm_ratio - 1) -- i.e. the
  # checkpoint-selection logic must be self-consistent with what's recorded
  # in history, not just "some" loss value.
  penalized <- fit$history$test_loss + 5 * (fit$history$norm_ratio - 1)
  expect_equal(fit$loss, fit$history$test_loss[which.min(penalized)])
})
