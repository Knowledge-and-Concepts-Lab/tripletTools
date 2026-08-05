trips <- make_fake_triplet_list()

test_that("prepare_triplet_matrices returns X_train/X_test/all_items with expected shapes", {
  mats <- prepare_triplet_matrices(trips, seed = 1L)

  expect_true(all(c("X_train", "X_test", "all_items") %in% names(mats)))
  expect_equal(ncol(mats$X_train), 3L)
  expect_equal(ncol(mats$X_test), 3L)
  expect_equal(colnames(mats$X_train), c("head", "winner", "loser"))

  all_item_names <- sort(unique(unlist(lapply(trips, function(df) {
    c(df$Center, df$Left, df$Right)
  }))))
  expect_equal(mats$all_items, all_item_names)

  # Indices must be zero-based and within range
  n_items <- length(mats$all_items)
  expect_true(all(mats$X_train >= 0 & mats$X_train < n_items))
  expect_true(all(mats$X_test >= 0 & mats$X_test < n_items))
})

test_that("prepare_triplet_matrices uses the sampleSet column when present", {
  mats <- prepare_triplet_matrices(trips, seed = 1L)
  n_train_expected <- sum(vapply(trips, function(df) sum(df$sampleSet == "train"), integer(1)))
  n_test_expected  <- sum(vapply(trips, function(df) sum(df$sampleSet == "test"), integer(1)))

  expect_equal(nrow(mats$X_train), n_train_expected)
  expect_equal(nrow(mats$X_test), n_test_expected)
})

test_that("prepare_triplet_matrices falls back to a random 70/30 split when sampleSet is absent", {
  no_split <- lapply(trips, function(df) { df$sampleSet <- NA; df })
  mats <- prepare_triplet_matrices(no_split, seed = 1L)

  n_total <- sum(vapply(no_split, nrow, integer(1)))
  expect_equal(nrow(mats$X_train) + nrow(mats$X_test), n_total)
  expect_equal(nrow(mats$X_train), floor(0.7 * n_total))

  # Same seed must give the same split (reproducibility)
  mats2 <- prepare_triplet_matrices(no_split, seed = 1L)
  expect_equal(mats$X_train, mats2$X_train)
  expect_equal(mats$X_test, mats2$X_test)
})
