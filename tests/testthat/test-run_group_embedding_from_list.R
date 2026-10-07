skip_if_not_installed("reticulate")
skip_if(
  inherits(tryCatch(.get_compute_py(), error = function(e) e), "error"),
  "Python embedding backend not available"
)

trips <- make_fake_triplet_list()
all_item_names <- sort(unique(unlist(lapply(trips, function(df) {
  c(df$Center, df$Left, df$Right)
}))))

# Epoch counts here are chosen to be as small as possible while still
# exercising the real training loop -- these tests check that the pipeline
# runs and returns the right shapes, not that it converges.

test_that("run_group_embedding_from_list runs and returns expected structure", {
  grp <- run_group_embedding_from_list(trips, d = 2L, max_epochs = 20L,
                                        tol_window = 10L, seed = 1L)

  expect_equal(ncol(grp$embedding), 2L)
  expect_equal(sort(rownames(grp$embedding)), all_item_names)
  expect_true(is.numeric(grp$loss))
  expect_s3_class(grp$history, "data.frame")
})

test_that("warm_start skips the warm-start stage and is matched by row name", {
  grp <- run_group_embedding_from_list(trips, d = 2L, max_epochs = 20L,
                                        tol_window = 10L, seed = 1L)
  shuffled <- grp$embedding[sample(nrow(grp$embedding)), , drop = FALSE]

  out_without <- reticulate::py_capture_output(
    run_group_embedding_from_list(trips, d = 2L, geometry = "sphere",
                                   max_epochs = 20L, tol_window = 10L, seed = 1L)
  )
  out_with <- reticulate::py_capture_output(
    run_group_embedding_from_list(trips, d = 2L, geometry = "sphere",
                                   max_epochs = 20L, tol_window = 10L, seed = 1L,
                                   warm_start = shuffled)
  )

  expect_true(grepl("spherical warm start", out_without, fixed = TRUE))
  expect_false(grepl("spherical warm start", out_with, fixed = TRUE))
})

test_that("warm_start validates row names against item names", {
  grp <- run_group_embedding_from_list(trips, d = 2L, max_epochs = 20L,
                                        tol_window = 10L, seed = 1L)

  no_names <- grp$embedding
  rownames(no_names) <- NULL
  expect_error(
    run_group_embedding_from_list(trips, d = 2L, geometry = "sphere",
                                   warm_start = no_names),
    "row names"
  )

  missing_item <- grp$embedding[-1, , drop = FALSE]
  expect_error(
    run_group_embedding_from_list(trips, d = 2L, geometry = "sphere",
                                   warm_start = missing_item),
    "missing"
  )
})

test_that("norm_penalty is accepted and forwarded without error", {
  grp <- run_group_embedding_from_list(trips, d = 2L, max_epochs = 20L,
                                        tol_window = 10L, seed = 1L,
                                        norm_penalty = 5)
  expect_equal(ncol(grp$embedding), 2L)
  expect_equal(sort(rownames(grp$embedding)), all_item_names)
})

test_that("same seed reproduces an identical embedding", {
  # Regression test for a real bug: seed was only passed to set.seed()
  # (R-level), never to train_embedding()'s own random_state, so two calls
  # with identical arguments -- including the same seed -- produced
  # different embeddings. Confirmed this would have failed before the fix.
  grp_a <- run_group_embedding_from_list(trips, d = 2L, max_epochs = 20L,
                                          tol_window = 10L, seed = 5L)
  grp_b <- run_group_embedding_from_list(trips, d = 2L, max_epochs = 20L,
                                          tol_window = 10L, seed = 5L)
  expect_identical(grp_a$embedding, grp_b$embedding)
})

test_that("a different seed gives a different embedding (not a degenerate fixed point)", {
  grp_a <- run_group_embedding_from_list(trips, d = 2L, max_epochs = 20L,
                                          tol_window = 10L, seed = 1L)
  grp_b <- run_group_embedding_from_list(trips, d = 2L, max_epochs = 20L,
                                          tol_window = 10L, seed = 2L)
  expect_false(identical(grp_a$embedding, grp_b$embedding))
})
