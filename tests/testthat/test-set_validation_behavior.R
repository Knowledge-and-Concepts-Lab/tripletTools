make_fixture <- function() {
  data.frame(
    worker_id = "p1",
    sampleAlg = c("random", "check", "validation", "validation"),
    sampleSet = c("train", NA, "train", "train")
  )
}

test_that("mode = 'train'/'test' set sampleSet to that string for validation rows", {
  d <- make_fixture()

  res_train <- set_validation_behavior(d, mode = "train")
  expect_true(all(res_train$sampleSet[d$sampleAlg == "validation"] == "train"))

  res_test <- set_validation_behavior(d, mode = "test")
  expect_true(all(res_test$sampleSet[d$sampleAlg == "validation"] == "test"))
})

test_that("mode = 'holdout' sets sampleSet to NA for validation rows only", {
  d <- make_fixture()
  res <- set_validation_behavior(d, mode = "holdout")

  expect_true(all(is.na(res$sampleSet[d$sampleAlg == "validation"])))
  # non-validation rows (random, check) are untouched
  expect_identical(res$sampleSet[d$sampleAlg != "validation"],
                    d$sampleSet[d$sampleAlg != "validation"])
})

test_that("works on a list of data frames, preserving names", {
  d <- make_fixture()
  triplet_list <- list(p1 = d, p2 = d)
  res <- set_validation_behavior(triplet_list, mode = "holdout")

  expect_named(res, c("p1", "p2"))
  for (df in res) {
    expect_true(all(is.na(df$sampleSet[df$sampleAlg == "validation"])))
  }
})

test_that("errors on missing columns or invalid input", {
  expect_error(
    set_validation_behavior(data.frame(sampleAlg = "random"), mode = "holdout"),
    "sampleAlg and"
  )
  expect_error(set_validation_behavior(42, mode = "holdout"), "data frame")
  expect_error(set_validation_behavior(make_fixture(), mode = "bogus"))
})
