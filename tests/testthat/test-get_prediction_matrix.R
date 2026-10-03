test_that("Prediction matrix is correctly generated", {
  pmat <- get.prediction.matrix(icon_emb_ind, icon_triplets, ttype="test")

  result <- round(pmat[1,1], 2)
  expected <- 0.69
  expect_equal(result, expected)
})

test_that("ttype = 'validation' passes through to get.hoacc() unfiltered", {
  # Regression test: get.prediction.matrix() used to pre-filter by
  # sampleSet == ttype before ever calling get.hoacc(), which would select
  # nothing for ttype = "validation" once validation trials are excluded
  # from training (sampleSet = NA). The fix removes that redundant
  # pre-filter and lets get.hoacc()'s own sampleAlg-based handling run on
  # the full, unfiltered data.
  m <- as.matrix(data.frame(
    x = c(1, 1.1, 2, 2.1),
    y = c(1.25, 1.75, 1.25, 1.75),
    row.names = c("cat", "dog", "car", "boat")
  ))
  tr <- data.frame(
    Center    = c("cat", "car", "dog", "boat"),
    Left      = c("dog", "boat", "car", "cat"),
    Right     = c("car", "dog", "boat", "car"),
    Answer    = c("dog", "boat", "car", "car"),
    sampleSet = c(NA, NA, "train", "train"),
    sampleAlg = c("validation", "validation", "random", "random")
  )

  pmat <- get.prediction.matrix(list(m1 = m), list(p1 = tr), ttype = "validation")
  expect_equal(pmat["m1", "p1"], 1.0)
})
