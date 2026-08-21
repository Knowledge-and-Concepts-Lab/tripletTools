skip_if_not_installed("reticulate")
skip_if(
  inherits(tryCatch(.get_compute_py(), error = function(e) e), "error"),
  "Python embedding backend not available"
)

n_items <- 8
items <- paste0("item", seq_len(n_items))
coords_a <- matrix(cbind(seq_len(n_items), 0), n_items, 2,
                    dimnames = list(items, c("x", "y")))
scramble <- c(1, 5, 2, 6, 3, 7, 4, 8)
coords_b <- matrix(cbind(scramble, 0), n_items, 2,
                    dimnames = list(items, c("x", "y")))

# Epoch/permutation counts here are as small as possible while still
# exercising the real fitting loop -- these tests check that the procedure
# runs correctly and points the right direction, not that it has real
# statistical power.

test_that("group_difference_test() returns expected structure", {
  trips_a <- make_structured_triplet_list(coords_a, n_participants = 4, n_trials = 100,
                                           worker_prefix = "a", seed = 1)
  trips_b <- make_structured_triplet_list(coords_b, n_participants = 4, n_trials = 100,
                                           worker_prefix = "b", seed = 2)
  trips <- c(trips_a, trips_b)
  names(trips) <- c(paste0("a", 1:4), paste0("b", 1:4))
  group <- setNames(rep(c("A", "B"), each = 4), names(trips))

  res <- group_difference_test(
    trips, group, d = 2L,
    n_permutations = 3L, max_epochs = 200L, tol_window = 100L,
    seed = 1, verbose = FALSE
  )

  expect_s3_class(res, "group_difference_test")
  expect_true(all(c("observed_correlation", "null_correlations", "p_value",
                     "settings") %in% names(res)))
  expect_length(res$null_correlations, 3L)
  expect_true(res$observed_correlation >= -1e-8 && res$observed_correlation <= 1 + 1e-8)
  expect_true(res$p_value > 0 && res$p_value <= 1)
  expect_equal(res$settings$group_sizes, c(4L, 4L))
})

test_that("group accepts a data frame with worker_id/group columns", {
  trips_a <- make_structured_triplet_list(coords_a, n_participants = 3, n_trials = 100,
                                           worker_prefix = "a", seed = 1)
  trips_b <- make_structured_triplet_list(coords_a, n_participants = 3, n_trials = 100,
                                           worker_prefix = "b", seed = 2)
  trips <- c(trips_a, trips_b)
  names(trips) <- c(paste0("a", 1:3), paste0("b", 1:3))
  group_df <- data.frame(worker_id = names(trips),
                          group = rep(c("A", "B"), each = 3),
                          stringsAsFactors = FALSE)

  res <- group_difference_test(
    trips, group_df, d = 2L,
    n_permutations = 2L, max_epochs = 200L, tol_window = 100L,
    seed = 1, verbose = FALSE
  )
  expect_s3_class(res, "group_difference_test")
})

test_that("group_difference_test() validates its inputs", {
  trips <- make_structured_triplet_list(coords_a, n_participants = 4, n_trials = 50, seed = 1)
  names(trips) <- paste0("p", 1:4)

  expect_error(
    group_difference_test(trips, setNames(rep("A", 4), names(trips)), d = 2L),
    "exactly two distinct values"
  )
  expect_error(
    group_difference_test(trips, setNames(c("A","A","A","B"), names(trips)), d = 2L),
    "at least 3 participants"
  )
  mismatched <- setNames(c("A","A","B","B"), c("p1","p2","p3","zzz"))
  expect_error(
    group_difference_test(trips, mismatched, d = 2L),
    "same participant IDs"
  )
  trips6 <- make_structured_triplet_list(coords_a, n_participants = 6, n_trials = 50, seed = 1)
  names(trips6) <- paste0("p", 1:6)
  expect_error(
    group_difference_test(trips6, setNames(rep(c("A","B"), each = 3), names(trips6)), d = 0L),
    "d must be at least 1"
  )
  expect_error(
    group_difference_test(trips6, setNames(rep(c("A","B"), each = 3), names(trips6)),
                           d = 2L, n_permutations = 0L),
    "n_permutations must be at least 1"
  )
})
