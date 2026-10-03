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
