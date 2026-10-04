make_traj_2d <- function(n_query = 20) {
  repdist <- get.rep.dist(icon_emb_ind)
  pos <- cmdscale(repdist, k = 1)[, 1]
  elist_2d <- lapply(icon_emb_ind, function(e) e[, 1:2])
  list(
    traj = smooth_embedding_trajectory(elist_2d, pos, n_query = n_query),
    pos = pos
  )
}

test_that("runs without error with and without pos", {
  pdf(NULL)
  on.exit(dev.off())
  fx <- make_traj_2d()

  expect_no_error(plot_2d_trajectory(fx$traj, pos = fx$pos, loc = 10))
  expect_no_error(plot_2d_trajectory(fx$traj, loc = 10))
})

test_that("... overrides plot()'s own defaults without erroring", {
  pdf(NULL)
  on.exit(dev.off())
  fx <- make_traj_2d()
  expect_no_error(plot_2d_trajectory(fx$traj, pos = fx$pos, loc = 10,
                                      main = "test", asp = 1))
})

test_that("custom pcols/bcols/pch/cex.symbols are accepted", {
  pdf(NULL)
  on.exit(dev.off())
  fx <- make_traj_2d()
  nitems <- nrow(fx$traj$embeddings[[1]])
  expect_no_error(plot_2d_trajectory(
    fx$traj, pos = fx$pos, loc = 10,
    pcols = rainbow(nitems), bcols = rep("black", nitems),
    pch = 19, cex.symbols = 2
  ))
})

test_that("restores the caller's par(mar) on exit", {
  pdf(NULL)
  on.exit(dev.off())
  fx <- make_traj_2d()

  original_mar <- graphics::par("mar")
  plot_2d_trajectory(fx$traj, pos = fx$pos, loc = 10)
  expect_equal(graphics::par("mar"), original_mar)
})

test_that("errors on an invalid loc", {
  pdf(NULL)
  on.exit(dev.off())
  fx <- make_traj_2d()
  n_query <- length(fx$traj$query_points)

  expect_error(plot_2d_trajectory(fx$traj, loc = 0), "between 1 and")
  expect_error(plot_2d_trajectory(fx$traj, loc = n_query + 1), "between 1 and")
  expect_error(plot_2d_trajectory(fx$traj, loc = 1.5), "between 1 and")
})

test_that("errors clearly on a non-2D trajectory", {
  pdf(NULL)
  on.exit(dev.off())
  traj_3d <- list(
    query_points = 1:3,
    embeddings = list(matrix(1:6, 2, 3), matrix(1:6, 2, 3), matrix(1:6, 2, 3)),
    effective_n = c(1, 1, 1)
  )
  expect_error(plot_2d_trajectory(traj_3d, loc = 1), "exactly 2 columns")
})

test_that("participant positions are mapped linearly onto the density strip's rendered extent", {
  pdf(NULL)
  on.exit(dev.off())
  fx <- make_traj_2d()
  plot_2d_trajectory(fx$traj, pos = fx$pos, loc = 10)

  rngs <- get_axis_ranges(fx$traj$embeddings)
  xr <- c(-1, 1) * max(abs(rngs$d1))
  d <- add_density_strip(xr, fx$traj$effective_n)

  qr <- range(fx$traj$query_points)
  expected_frac <- (fx$pos - qr[1]) / diff(qr)
  expected_x <- d$xlim[1] + expected_frac * diff(d$xlim)

  expect_equal(min(expected_x), d$xlim[1])
  expect_equal(max(expected_x), d$xlim[2])
})
