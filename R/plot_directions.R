#' Scatterplot with directional arrows
#'
#' Like a standard scatterplot of 2D coordinates, but represents each point
#' as an arrow centered on its (x, y) location and pointing in a specified
#' direction, with a small dot marking the exact coordinate. Useful for
#' visualizing an embedding of motion stimuli (e.g. random-dot kinetograms)
#' alongside the direction each one represents.
#'
#' @importFrom grDevices xy.coords
#' @importFrom graphics plot points arrows
#'
#' @param x A numeric vector of x-coordinates, or a two-column matrix/data
#'   frame of (x, y) coordinates (in which case \code{y} is taken from its
#'   second column). Mirrors the flexible \code{x}/\code{y} handling of
#'   \code{\link[graphics]{plot}}.
#' @param y Numeric vector of y-coordinates. Not needed if \code{x} already
#'   supplies both columns.
#' @param z Numeric vector giving each point's direction in degrees,
#'   counter-clockwise from rightward (\code{0} = right, \code{90} = up,
#'   \code{180} = left, \code{270} = down). Recycled if length 1.
#' @param length Numeric. Length of each arrow from tail to tip, expressed as
#'   a fraction of the plotted data's span (the larger of the x- and y-range)
#'   rather than an absolute value, so arrows scale sensibly regardless of
#'   the units \code{x}/\code{y} are in. Arrows are centered on their
#'   coordinate, so each extends \code{length / 2} of that span to either
#'   side of the point. Default \code{0.05} (5% of the plotted range).
#' @param col Color for the arrows, and by default the center dots too.
#'   Recycled across points as usual.
#' @param point_col Color for the center dots marking each (x, y) location.
#'   Defaults to \code{col}.
#' @param point_pch,point_cex Plotting character and size for the center
#'   dots. Set \code{point_pch = NA} to omit them.
#' @param head_length Numeric. Length of the arrowhead edges, in inches.
#'   Passed as \code{length} to \code{\link[graphics]{arrows}}. Default
#'   \code{0.08}.
#' @param head_angle Numeric. Angle in degrees between the arrowhead edges
#'   and the shaft. Passed as \code{angle} to \code{\link[graphics]{arrows}}.
#'   Default \code{25}.
#' @param lwd Line width for the arrows.
#' @param add Logical. If \code{TRUE}, add arrows to an existing plot instead
#'   of starting a new one (all plot-setup arguments below are then
#'   ignored). Default \code{FALSE}.
#' @param asp Numeric aspect ratio passed to \code{\link[graphics]{plot}}
#'   when \code{add = FALSE}. Default \code{1}, so that a stimulus's
#'   direction is not visually distorted by unequal x/y scaling; set to
#'   \code{NA} to use the device default instead.
#' @param xlab,ylab,xlim,ylim,main Passed to \code{\link[graphics]{plot}}
#'   when \code{add = FALSE}.
#' @param ... Further arguments passed to \code{\link[graphics]{plot}} when
#'   \code{add = FALSE}.
#'
#' @return Invisibly returns a data frame with columns \code{x}, \code{y},
#'   \code{z} and the arrow endpoints \code{x0}, \code{y0}, \code{x1},
#'   \code{y1}. Called chiefly for its side effect of drawing on the current
#'   graphics device.
#'
#' @export
#'
#' @examples
#' set.seed(1)
#' x <- rnorm(8)
#' y <- rnorm(8)
#' z <- seq(0, 315, by = 45)
#' plot_directions(x, y, z, length = 0.15, col = "steelblue")
plot_directions <- function(
    x, y = NULL, z,
    length      = 0.05,
    col         = "black",
    point_col   = col,
    point_pch   = 16,
    point_cex   = 0.7,
    head_length = 0.08,
    head_angle  = 25,
    lwd         = 1,
    add         = FALSE,
    asp         = 1,
    xlab        = "Dimension 1",
    ylab        = "Dimension 2",
    xlim        = NULL,
    ylim        = NULL,
    main        = NULL,
    ...) {

  ### Check arguments
  # If x already supplies both coordinates (a matrix/data frame with >= 2
  # columns) and z was not itself given a value, the second positional
  # argument can only sensibly be z, not y -- e.g.
  # plot_directions(embedding[, 1:2], directions, col = "red"). Ordinary R
  # positional matching can't know this on its own (it resolves purely by
  # argument position, before looking at any values), so handle it here.
  if (missing(z) && !is.null(y) &&
      (is.matrix(x) || is.data.frame(x)) && ncol(x) >= 2 &&
      length(y) == nrow(x)) {
    z <- y
    y <- NULL
    message("plot_directions(): `x` supplies both coordinates, so treating ",
            "the second argument as `z` (direction).")
  }
  if (missing(z)) {
    stop("z (direction in degrees) must be supplied, e.g. z = my_angles.")
  }

  xy <- grDevices::xy.coords(x, y)
  x  <- xy$x
  y  <- xy$y

  if (length(z) == 1) z <- rep(z, length(x))
  if (length(z) != length(x)) {
    stop("z must have length 1 or the same length as x/y")
  }

  ### Arrow length is a fraction of the data's span (larger of the x/y
  ### range), not an absolute value, so it scales sensibly with the data
  ### regardless of the units x/y happen to be in.
  span      <- max(diff(range(x)), diff(range(y)))
  arrow_len <- length * span

  ### Arrow endpoints: centered on (x, y), pointing toward z
  theta <- z * pi / 180
  dx <- (arrow_len / 2) * cos(theta)
  dy <- (arrow_len / 2) * sin(theta)

  x0 <- x - dx
  y0 <- y - dy
  x1 <- x + dx
  y1 <- y + dy

  ### Set up plotting region
  if (!add) {
    if (is.null(xlim)) xlim <- range(c(x0, x1))
    if (is.null(ylim)) ylim <- range(c(y0, y1))
    plot(x, y, type = "n", xlab = xlab, ylab = ylab,
         xlim = xlim, ylim = ylim, asp = asp, main = main, ...)
  }

  ### Draw arrows and center points
  arrows(x0, y0, x1, y1, length = head_length, angle = head_angle,
         code = 2, col = col, lwd = lwd)

  if (!identical(point_pch, NA)) {
    points(x, y, pch = point_pch, col = point_col, cex = point_cex)
  }

  invisible(data.frame(x = x, y = y, z = z, x0 = x0, y0 = y0, x1 = x1, y1 = y1))
}
