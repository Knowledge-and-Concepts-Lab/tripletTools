test_that("Reading a combined data file works", {

  fpath <- system.file("extdata", "icon_embeddings_individual.csv", package="tripletTools")
  tmp <- get.combined(fpath, eflag=TRUE)
  tmp <- tmp[[1]]
  result <- round(tmp[1,1],2)
  expect_equal(result, 0.64)
})

test_that("worker_id stays character even when every value looks numeric, preserving leading zeros", {

  df <- data.frame(
    worker_id = c("0012345678", "0012345678", "9876543210", "9876543210"),
    Center = c("a", "b", "a", "b"), Left = c("b", "c", "b", "c"),
    Right = c("c", "a", "c", "a"), Answer = c("b", "c", "b", "c"),
    sampleAlg = "random", sampleSet = "train"
  )
  fpath <- tempfile(fileext = ".csv")
  write.csv(df, fpath, row.names = FALSE, quote = FALSE)

  tmp <- get.combined(fpath)

  expect_type(tmp[[1]]$worker_id, "character")
  expect_setequal(names(tmp), c("0012345678", "9876543210"))
  # the specific failure mode this guards against: read.csv()'s default type
  # inference reads an all-digit worker_id column as numeric, silently
  # dropping the leading zero and splitting what should be one participant's
  # 2 rows into a dangling, unmatched entry
  expect_equal(nrow(tmp[["0012345678"]]), 2)
})
