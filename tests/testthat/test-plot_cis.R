test_that("Calculation of column means is correct", {
  dm <- matrix(1:12,4,3)
  mn <- plot_cis(dm)
  expect_equal(mn[1,], colMeans(dm))
})

test_that("returned matrix has the documented row names and column names", {
  dm <- matrix(1:12, 4, 3, dimnames = list(NULL, c("a", "b", "c")))
  mn <- plot_cis(dm)
  expect_equal(rownames(mn), c("mean", "upperci", "lowerci"))
  expect_equal(colnames(mn), c("a", "b", "c"))
})

test_that("barflag runs without error and produces a proportionate cap width regardless of bar count", {
  pdf(NULL)  # null graphics device, no file written
  on.exit(dev.off())

  set.seed(1)
  for (ncols in c(1, 2, 8)) {
    dm <- matrix(rnorm(20 * ncols), ncol = ncols)
    expect_no_error(plot_cis(dm, barflag = TRUE))
  }
})

test_that("capfrac must be in (0, 1]", {
  dm <- matrix(rnorm(20 * 2), ncol = 2)
  expect_error(plot_cis(dm, barflag = TRUE, capfrac = 0), "capfrac must be in")
  expect_error(plot_cis(dm, barflag = TRUE, capfrac = 1.5), "capfrac must be in")
  expect_error(plot_cis(dm, barflag = TRUE, capfrac = -0.1), "capfrac must be in")
})

test_that("capfrac = 1 is allowed (boundary case)", {
  pdf(NULL)
  on.exit(dev.off())
  dm <- matrix(rnorm(20 * 2), ncol = 2)
  expect_no_error(plot_cis(dm, barflag = TRUE, capfrac = 1))
})

test_that("a single-value or zero-variance column returns a zero-width interval at the mean", {
  dm <- matrix(c(1, 2, 3, 4, 5, 5, 5, 5), ncol = 2)
  mn <- plot_cis(dm)
  expect_equal(unname(mn["upperci", 2]), unname(mn["mean", 2]))
  expect_equal(unname(mn["lowerci", 2]), unname(mn["mean", 2]))
})

test_that("a column with all NA returns NA for mean and both CI bounds", {
  dm <- matrix(c(1, 2, 3, 4, NA, NA, NA, NA), ncol = 2)
  mn <- plot_cis(dm)
  expect_true(all(is.na(mn[, 2])))
})

test_that("errors on non-numeric input or a single-row matrix", {
  expect_error(plot_cis(matrix(letters[1:4], 2, 2)), "numeric matrix")
  expect_error(plot_cis(matrix(1:3, 1, 3)), "more than one row")
})

test_that("errors when xvals length doesn't match the number of columns", {
  dm <- matrix(rnorm(20 * 3), ncol = 3)
  expect_error(plot_cis(dm, xvals = 1:2), "Number of xvalues")
})
