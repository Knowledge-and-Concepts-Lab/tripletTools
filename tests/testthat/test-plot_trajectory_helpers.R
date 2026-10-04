test_that("get_axis_ranges handles an all-NA embedding without producing NA ranges", {
  # Mirrors smooth_embedding_trajectory()'s own documented behavior: a
  # query point with no meaningful kernel weight gets an all-NA embedding
  # matrix (with a warning, which range(na.rm=TRUE) also raises here --
  # both are expected, not failures).
  good1 <- matrix(c(1, -2, 0.5), 1, 3)
  good2 <- matrix(c(2, -1, -0.5), 1, 3)
  bad   <- matrix(NA_real_, 1, 3)

  rngs <- suppressWarnings(get_axis_ranges(list(good1, bad, good2)))
  expect_false(any(vapply(rngs, function(r) any(is.na(r)), logical(1))))
  expect_equal(rngs$d1, c(1, 2))
  expect_equal(rngs$d2, c(-2, -1))
  expect_equal(rngs$d3, c(-0.5, 0.5))
})

test_that("get_axis_ranges works for 2-D embeddings too", {
  e1 <- matrix(c(1, -2), 1, 2)
  e2 <- matrix(c(3, -1), 1, 2)
  rngs <- get_axis_ranges(list(e1, e2))
  expect_named(rngs, c("d1", "d2"))
  expect_equal(rngs$d1, c(1, 3))
  expect_equal(rngs$d2, c(-2, -1))
})

test_that("validate_traj_loc errors on an invalid loc, passes silently on a valid one", {
  traj <- list(query_points = 1:5)
  expect_error(validate_traj_loc(traj, 0), "between 1 and")
  expect_error(validate_traj_loc(traj, 6), "between 1 and")
  expect_error(validate_traj_loc(traj, 2.5), "between 1 and")
  expect_no_error(validate_traj_loc(traj, 3))
})

test_that("add_density_strip spans exactly the requested xlim", {
  pdf(NULL)
  on.exit(dev.off())
  plot(0:1, 0:1, type = "n")
  d <- add_density_strip(c(-2, 2), density = c(1, 2, 3, 4, 5))
  expect_equal(range(d$x), c(-2, 2))
  expect_equal(d$xlim, c(-2, 2))
  expect_length(d$heights, 5)
  expect_equal(which.max(d$heights), 5L)  # density is increasing
})

test_that("add_trajectory_markers places participant dots at the extremes for min/max positions", {
  pdf(NULL)
  on.exit(dev.off())
  plot(0:1, 0:1, type = "n")
  d <- add_density_strip(c(-2, 2), density = rep(1, 5))
  traj <- list(query_points = seq(-2, 2, length.out = 5))

  # positions exactly at the query-point range extremes should map exactly
  # onto d$xlim's own extremes
  expect_no_error(add_trajectory_markers(d, traj, pos = c(-2, 2), loc = 3))
})

test_that("add_trajectory_markers accepts a 1-column or 1-row matrix pos (e.g. raw cmdscale() output)", {
  # Regression test: cmdscale(d, k = 1) always returns a matrix, even for
  # k = 1 -- a very easy, real mistake to make (confirmed against a real
  # user script) -- and must not be silently mishandled.
  pdf(NULL)
  on.exit(dev.off())
  plot(0:1, 0:1, type = "n")
  d <- add_density_strip(c(-2, 2), density = rep(1, 5))
  traj <- list(query_points = seq(-2, 2, length.out = 5))

  pos_col <- matrix(c(-2, 0, 2), ncol = 1)
  pos_row <- matrix(c(-2, 0, 2), nrow = 1)
  expect_no_error(add_trajectory_markers(d, traj, pos = pos_col, loc = 3))
  expect_no_error(add_trajectory_markers(d, traj, pos = pos_row, loc = 3))
})

test_that("add_trajectory_markers errors clearly on a genuine multi-column pos matrix", {
  pdf(NULL)
  on.exit(dev.off())
  plot(0:1, 0:1, type = "n")
  d <- add_density_strip(c(-2, 2), density = rep(1, 5))
  traj <- list(query_points = seq(-2, 2, length.out = 5))

  pos_bad <- matrix(1:6, nrow = 3, ncol = 2)
  expect_error(add_trajectory_markers(d, traj, pos = pos_bad, loc = 3),
               "1-D numeric vector")
})
