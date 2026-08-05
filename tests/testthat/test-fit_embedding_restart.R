skip_if_not_installed("reticulate")
skip_if(
  inherits(tryCatch(.get_compute_py(), error = function(e) e), "error"),
  "Python embedding backend not available"
)

trips <- make_fake_triplet_list()
mats  <- prepare_triplet_matrices(trips, seed = 1L)

test_that("fit_embedding_restart returns the expected one-row structure", {
  row <- fit_embedding_restart(
    X_train = mats$X_train, X_test = mats$X_test, d = 2L, random_state = 0L,
    max_epochs = 20L, tolerance = 1e-4, tol_window = 10L, device = "cpu",
    geometry = "euclidean", radius = 1, norm_penalty = 0
  )

  expect_equal(nrow(row), 1L)
  expect_true(all(c("loss", "accuracy", "epoch_stopped", "epoch_best", "norm_ratio") %in%
                    names(row)))
  expect_true(row$accuracy >= 0 && row$accuracy <= 1)
  expect_true(row$norm_ratio >= 1 - 1e-8)
})

test_that("fit_embedding_restart is deterministic given the same random_state", {
  row1 <- fit_embedding_restart(
    X_train = mats$X_train, X_test = mats$X_test, d = 2L, random_state = 5L,
    max_epochs = 20L, tolerance = 1e-4, tol_window = 10L, device = "cpu",
    geometry = "euclidean", radius = 1, norm_penalty = 0
  )
  row2 <- fit_embedding_restart(
    X_train = mats$X_train, X_test = mats$X_test, d = 2L, random_state = 5L,
    max_epochs = 20L, tolerance = 1e-4, tol_window = 10L, device = "cpu",
    geometry = "euclidean", radius = 1, norm_penalty = 0
  )
  expect_equal(row1, row2)
})
