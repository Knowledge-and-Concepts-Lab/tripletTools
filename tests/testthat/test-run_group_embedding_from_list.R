skip_if_not_installed("reticulate")
skip_if(
  inherits(tryCatch(.get_compute_py(), error = function(e) e), "error"),
  "Python embedding backend not available"
)

# Small synthetic triplet_list fixture, structured like icon_triplets, used
# only to exercise the pipeline end to end -- not to check fit quality.
make_fake_triplet_list <- function(n_participants = 2L, n_items = 5L,
                                    n_trials = 30L, seed = 1L) {
  set.seed(seed)
  items <- paste0("item", seq_len(n_items))
  lapply(seq_len(n_participants), function(p) {
    center <- sample(items, n_trials, replace = TRUE)
    left   <- vapply(center, function(c) sample(setdiff(items, c), 1), character(1))
    right  <- mapply(function(c, l) sample(setdiff(items, c(c, l)), 1), center, left)
    answer <- ifelse(stats::runif(n_trials) < 0.5, left, right)
    data.frame(
      Center = center, Left = left, Right = right, Answer = answer,
      sampleSet = rep(c("train", "test"), length.out = n_trials),
      sampleAlg = "random",
      worker_id = paste0("p", p),
      stringsAsFactors = FALSE
    )
  })
}

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
