make_fixture <- function() {
  list(
    p1 = data.frame(worker_id = "p1", sampleSet = rep(c("train", "test"), 5)),
    p2 = data.frame(worker_id = "p2", sampleSet = rep(c("train", "test"), 5))
  )
}

test_that("flips sampleSet to 'train' exactly at the given positions", {
  trips <- make_fixture()
  combined_before <- do.call(rbind, trips)
  test_rows <- which(combined_before$sampleSet == "test")

  # Fold back only the first half of the test rows.
  rows_to_fold <- test_rows[seq_len(length(test_rows) %/% 2)]
  folded <- fold_alpha_test_to_train(trips, rows_to_fold)

  combined_after <- do.call(rbind, folded)
  expect_true(all(combined_after$sampleSet[rows_to_fold] == "train"))

  untouched_test_rows <- setdiff(test_rows, rows_to_fold)
  expect_true(all(combined_after$sampleSet[untouched_test_rows] == "test"))

  # Every row not in rows_to_fold is completely unchanged.
  unchanged <- setdiff(seq_len(nrow(combined_before)), rows_to_fold)
  expect_identical(combined_before$sampleSet[unchanged], combined_after$sampleSet[unchanged])
})

test_that("preserves list length, names, and order", {
  trips <- make_fixture()
  folded <- fold_alpha_test_to_train(trips, alpha_test_rows = integer(0))
  expect_identical(names(folded), names(trips))
  expect_equal(length(folded), length(trips))
})

test_that("preserves order on an unnamed triplet_list", {
  trips <- unname(make_fixture())
  folded <- fold_alpha_test_to_train(trips, alpha_test_rows = 1L)
  expect_null(names(folded))
  expect_equal(length(folded), 2)
})

test_that("works end to end with estimate_group_alpha()'s own alpha_test_rows", {
  skip_if_not_installed("reticulate")
  skip_if(
    inherits(tryCatch(.get_compute_py(), error = function(e) e), "error"),
    "Python embedding backend not available"
  )

  n_items <- 6
  items <- paste0("item", seq_len(n_items))
  true_coords <- matrix(cbind(seq_len(n_items), 0), n_items, 2,
                         dimnames = list(items, c("x", "y")))
  trips <- make_structured_triplet_list(true_coords, n_participants = 4, n_trials = 80, seed = 1)
  names(trips) <- paste0("p", 1:4)

  grp <- run_group_embedding_from_list(trips, d = 2L, max_epochs = 50L, tol_window = 20L, seed = 1L)
  joint <- estimate_group_alpha(
    trips, warm_start = grp$embedding,
    max_epochs = 50L, tol_window = 20L, max_outer = 1L, seed = 1L,
    alpha_test_frac = 0.4, verbose = FALSE
  )

  folded <- fold_alpha_test_to_train(trips, joint$alpha_test_rows)

  combined_before <- do.call(rbind, trips)
  combined_after  <- do.call(rbind, folded)

  n_test_before <- sum(combined_before$sampleSet == "test", na.rm = TRUE)
  n_test_after  <- sum(combined_after$sampleSet == "test", na.rm = TRUE)
  expect_equal(n_test_before - n_test_after, joint$n_alpha_test)

  # The folded-back rows are now "train"; everything else is unchanged.
  expect_true(all(combined_after$sampleSet[joint$alpha_test_rows] == "train"))
})

test_that("errors clearly on malformed input", {
  trips <- make_fixture()
  expect_error(fold_alpha_test_to_train(trips[[1]], 1L), "list of per-participant")
  expect_error(fold_alpha_test_to_train(list(), 1L), "empty")

  no_sample_set <- list(data.frame(worker_id = "p1"))
  expect_error(fold_alpha_test_to_train(no_sample_set, 1L), "sampleSet")

  expect_error(fold_alpha_test_to_train(trips, NA_integer_), "non-missing")
  expect_error(fold_alpha_test_to_train(trips, 9999L), "do.call\\(rbind")
  expect_error(fold_alpha_test_to_train(trips, 0L), "do.call\\(rbind")
})
