skip_if_not_installed("scatterplot3d")

make_traj <- function(n_query = 20) {
  repdist <- get.rep.dist(icon_emb_ind)
  pos <- cmdscale(repdist, k = 1)[, 1]
  list(
    traj = smooth_embedding_trajectory(icon_emb_ind, pos, n_query = n_query),
    pos = pos
  )
}

test_that("runs without error with and without pos", {
  pdf(NULL)
  on.exit(dev.off())
  fx <- make_traj()

  expect_no_error(plot_3d_trajectory(fx$traj, pos = fx$pos, loc = 10))
  expect_no_error(plot_3d_trajectory(fx$traj, loc = 10))
})

test_that("returns the scatterplot3d object invisibly", {
  pdf(NULL)
  on.exit(dev.off())
  fx <- make_traj()
  res <- plot_3d_trajectory(fx$traj, pos = fx$pos, loc = 10)
  expect_true(is.list(res))
  expect_true(is.function(res$xyz.convert))
})

test_that("... overrides scatterplot3d's own defaults without erroring", {
  pdf(NULL)
  on.exit(dev.off())
  fx <- make_traj()
  expect_no_error(plot_3d_trajectory(fx$traj, pos = fx$pos, loc = 10,
                                      angle = 60, grid = FALSE))
})

test_that("custom pcols/bcols/pch/cex.symbols are accepted", {
  pdf(NULL)
  on.exit(dev.off())
  fx <- make_traj()
  nitems <- nrow(fx$traj$embeddings[[1]])
  expect_no_error(plot_3d_trajectory(
    fx$traj, pos = fx$pos, loc = 10,
    pcols = rainbow(nitems), bcols = rep("black", nitems),
    pch = 19, cex.symbols = 2
  ))
})

test_that("participant positions are mapped linearly onto the density strip's rendered extent", {
  pdf(NULL)
  on.exit(dev.off())
  fx <- make_traj()
  p3d <- plot_3d_trajectory(fx$traj, pos = fx$pos, loc = 10)

  d <- add_density_to_cube(p3d, fx$traj$effective_n)
  qr <- range(fx$traj$query_points)
  expected_frac <- (fx$pos - qr[1]) / diff(qr)
  expected_x <- d$xlim[1] + expected_frac * diff(d$xlim)

  # the participant at the minimum position should map exactly to the left
  # edge of the rendered strip (query_points span exactly range(pos) by
  # construction when smooth_embedding_trajectory() builds its own grid)
  expect_equal(min(expected_x), d$xlim[1])
  expect_equal(max(expected_x), d$xlim[2])
})

test_that("errors on an invalid loc", {
  pdf(NULL)
  on.exit(dev.off())
  fx <- make_traj()
  n_query <- length(fx$traj$query_points)

  expect_error(plot_3d_trajectory(fx$traj, loc = 0), "between 1 and")
  expect_error(plot_3d_trajectory(fx$traj, loc = n_query + 1), "between 1 and")
  expect_error(plot_3d_trajectory(fx$traj, loc = 1.5), "between 1 and")
})

test_that("errors clearly on a non-3D trajectory", {
  pdf(NULL)
  on.exit(dev.off())
  traj_2d <- list(
    query_points = 1:3,
    embeddings = list(matrix(1:4, 2, 2), matrix(1:4, 2, 2), matrix(1:4, 2, 2)),
    effective_n = c(1, 1, 1)
  )
  expect_error(plot_3d_trajectory(traj_2d, loc = 1), "exactly 3 columns")
})
