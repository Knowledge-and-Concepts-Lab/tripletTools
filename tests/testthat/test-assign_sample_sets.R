make_fixture <- function() {
  data.frame(
    worker_id = rep("p1", 12),
    sampleAlg = c(rep("random", 6), rep("check", 2), rep("validation", 4))
  )
}

test_that("check trials always get sampleSet = NA regardless of validation_mode", {
  for (mode in c("train", "test", "holdout")) {
    res <- assign_sample_sets(make_fixture(), test_prop = 0.2, seed = 1,
                               validation_mode = mode)
    expect_true(all(is.na(res$sampleSet[res$sampleAlg == "check"])))
  }
})

test_that("validation_mode = 'train' sends all validation trials to train", {
  res <- assign_sample_sets(make_fixture(), test_prop = 0.2, seed = 1,
                             validation_mode = "train")
  expect_true(all(res$sampleSet[res$sampleAlg == "validation"] == "train"))
})

test_that("validation_mode = 'test' sends all validation trials to test", {
  res <- assign_sample_sets(make_fixture(), test_prop = 0.2, seed = 1,
                             validation_mode = "test")
  expect_true(all(res$sampleSet[res$sampleAlg == "validation"] == "test"))
})

test_that("validation_mode = 'holdout' excludes validation trials (sampleSet = NA)", {
  res <- assign_sample_sets(make_fixture(), test_prop = 0.2, seed = 1,
                             validation_mode = "holdout")
  expect_true(all(is.na(res$sampleSet[res$sampleAlg == "validation"])))
})

test_that("validation_mode doesn't change the random-trial split", {
  d <- make_fixture()
  res_train   <- assign_sample_sets(d, test_prop = 0.2, seed = 1, validation_mode = "train")
  res_holdout <- assign_sample_sets(d, test_prop = 0.2, seed = 1, validation_mode = "holdout")

  random_idx <- d$sampleAlg == "random"
  expect_identical(res_train$sampleSet[random_idx], res_holdout$sampleSet[random_idx])
})

test_that("validation_mode defaults to 'train' and rejects invalid values", {
  res <- assign_sample_sets(make_fixture(), test_prop = 0.2, seed = 1)
  expect_true(all(res$sampleSet[res$sampleAlg == "validation"] == "train"))

  expect_error(
    assign_sample_sets(make_fixture(), validation_mode = "bogus"),
    "should be one of"
  )
})

test_that("test-set count per participant is exact, not just approximately test_prop", {
  # 20 "random" trials, test_prop = 0.3 -> exactly 6 test trials, every time,
  # not merely 6 in expectation (as an independent per-trial coin flip would give).
  d <- data.frame(worker_id = rep("p1", 20), sampleAlg = rep("random", 20))
  for (s in 1:10) {
    res <- assign_sample_sets(d, test_prop = 0.3, seed = s)
    expect_equal(sum(res$sampleSet == "test"), 6)
  }
})

test_that("participants with the same number of random trials get the same test count", {
  d <- data.frame(
    worker_id = c(rep("p1", 10), rep("p2", 10)),
    sampleAlg = rep("random", 20)
  )
  res <- assign_sample_sets(d, test_prop = 0.4, seed = 1)
  n1 <- sum(res$sampleSet[res$worker_id == "p1"] == "test")
  n2 <- sum(res$sampleSet[res$worker_id == "p2"] == "test")
  expect_equal(n1, 4)
  expect_equal(n2, 4)
})

test_that("test count rounds to the nearest integer and handles the extremes", {
  d <- data.frame(worker_id = rep("p1", 7), sampleAlg = rep("random", 7))
  # round(0.3 * 7) = round(2.1) = 2
  res <- assign_sample_sets(d, test_prop = 0.3, seed = 1)
  expect_equal(sum(res$sampleSet == "test"), 2)

  res0 <- assign_sample_sets(d, test_prop = 0, seed = 1)
  expect_equal(sum(res0$sampleSet == "test"), 0)

  res1 <- assign_sample_sets(d, test_prop = 1, seed = 1)
  expect_equal(sum(res1$sampleSet == "test"), 7)
})

test_that("a participant with zero random trials doesn't error", {
  d <- data.frame(worker_id = "p1", sampleAlg = "check")
  expect_no_error(assign_sample_sets(d, test_prop = 0.2, seed = 1))
})
