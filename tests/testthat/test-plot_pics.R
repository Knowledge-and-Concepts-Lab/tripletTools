test_that("compute_pic_halfsize reproduces the old square-everything case exactly", {
  # Square device (pin), square axis ranges, square image: the box should
  # come out identical to the pre-fix formula psize * range for both axes.
  sz <- compute_pic_halfsize(native_ar = 1, psize = 0.05,
                              pin = c(6, 6), xlim = c(0, 10), ylim = c(0, 10))
  expect_equal(sz[["xsz"]], 0.05 * 10)
  expect_equal(sz[["ysz"]], 0.05 * 10)
})

test_that("compute_pic_halfsize keeps the correct physical aspect ratio on a non-square device", {
  # A square image (native_ar = 1) on a device that's twice as wide as it
  # is tall (pin = c(8, 4)), with square axis ranges, must still render
  # with a square *physical* footprint -- i.e. the physical width and
  # physical height (half-size in data units * inches-per-data-unit) must
  # be equal, even though pin itself is not square.
  pin <- c(8, 4)
  xlim <- c(0, 10)
  ylim <- c(0, 10)
  sz <- compute_pic_halfsize(native_ar = 1, psize = 0.05, pin = pin, xlim = xlim, ylim = ylim)

  x_per_in <- (xlim[2] - xlim[1]) / pin[1]
  y_per_in <- (ylim[2] - ylim[1]) / pin[2]
  physical_width  <- sz[["xsz"]] / x_per_in
  physical_height <- sz[["ysz"]] / y_per_in

  expect_equal(physical_width, physical_height)
})

test_that("compute_pic_halfsize preserves a non-square image's native aspect ratio on a non-square device", {
  # A 2:1 (wide) image on a device that's also non-square and has
  # non-square axis ranges -- the physical width/height ratio of the
  # rendered box must equal the image's own native_ar regardless.
  native_ar <- 2
  pin  <- c(5, 9)
  xlim <- c(-3, 7)   # range 10
  ylim <- c(0, 4)    # range 4
  sz <- compute_pic_halfsize(native_ar, psize = 0.1, pin = pin, xlim = xlim, ylim = ylim)

  x_per_in <- (xlim[2] - xlim[1]) / pin[1]
  y_per_in <- (ylim[2] - ylim[1]) / pin[2]
  physical_width  <- sz[["xsz"]] / x_per_in
  physical_height <- sz[["ysz"]] / y_per_in

  expect_equal(physical_width / physical_height, native_ar)
})

test_that("plot_pics() runs without error for square and non-square images on a non-square device", {
  square_img <- array(0, dim = c(10, 10, 4))
  wide_img   <- array(0, dim = c(10, 20, 4))  # native_ar = 2
  tall_img   <- array(0, dim = c(20, 10, 4))  # native_ar = 0.5

  pdf(NULL, width = 8, height = 3) # non-square device
  on.exit(dev.off())

  md <- matrix(c(0, 0, 1, 1, 2, 2), ncol = 2, byrow = TRUE)
  expect_no_error(
    plot_pics(md, list(square_img, wide_img, tall_img), psize = 0.1)
  )
})
