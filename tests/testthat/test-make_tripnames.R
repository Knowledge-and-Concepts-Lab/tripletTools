test_that("making triplet names works", {
  trips <- icon_triplets[[1]] #Triplet data for participant 1
  tnames <- make.tripnames(trips) #Make triplet names

  result <- tnames[1] #First triplet name
  expected <- "pnhns_pdcos_pncnb"
  expect_equal(result, expected)
})

test_that("works when Center/Left/Right are integer item indices, not strings", {
  # Regression test: as.matrix() on integer Left/Right columns produces an
  # integer matrix; gsub() on a non-character matrix used to coerce it via
  # as.character(), silently dropping the matrix's dim attribute and
  # breaking dim(opts)[1] downstream -- confirmed to throw
  # "Error in 1:nitems : argument of length 0" on real integer-coded data.
  df <- data.frame(worker_id = c("p1", "p2"),
                    Center = c(1L, 2L), Left = c(2L, 1L), Right = c(3L, 3L),
                    Answer = c(2L, 1L), stringsAsFactors = FALSE)

  tnames <- expect_no_error(make.tripnames(df))
  expect_equal(tnames, c("1_2_3", "2_1_3"))

  # Multi-row case (dim(opts)[1] > 1) is the one that actually exercises the
  # dropped-dim bug -- a single row alone wouldn't have caught it.
  expect_length(tnames, 2L)
})
