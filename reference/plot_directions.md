# Scatterplot with directional arrows

Like a standard scatterplot of 2D coordinates, but represents each point
as an arrow centered on its (x, y) location and pointing in a specified
direction, with a small dot marking the exact coordinate. Useful for
visualizing an embedding of motion stimuli (e.g. random-dot kinetograms)
alongside the direction each one represents.

## Usage

``` r
plot_directions(
  x,
  y = NULL,
  z,
  length = 0.05,
  col = "black",
  point_col = col,
  point_pch = 16,
  point_cex = 0.7,
  head_length = 0.08,
  head_angle = 25,
  lwd = 1,
  add = FALSE,
  asp = 1,
  xlab = "Dimension 1",
  ylab = "Dimension 2",
  xlim = NULL,
  ylim = NULL,
  main = NULL,
  ...
)
```

## Arguments

- x:

  A numeric vector of x-coordinates, or a two-column matrix/data frame
  of (x, y) coordinates (in which case `y` is taken from its second
  column). Mirrors the flexible `x`/`y` handling of
  [`plot`](https://rdrr.io/r/graphics/plot.default.html).

- y:

  Numeric vector of y-coordinates. Not needed if `x` already supplies
  both columns.

- z:

  Numeric vector giving each point's direction in degrees,
  counter-clockwise from rightward (`0` = right, `90` = up, `180` =
  left, `270` = down). Recycled if length 1.

- length:

  Numeric. Length of each arrow from tail to tip, expressed as a
  fraction of the plotted data's span (the larger of the x- and y-range)
  rather than an absolute value, so arrows scale sensibly regardless of
  the units `x`/`y` are in. Arrows are centered on their coordinate, so
  each extends `length / 2` of that span to either side of the point.
  Default `0.05` (5% of the plotted range).

- col:

  Color for the arrows, and by default the center dots too. Recycled
  across points as usual.

- point_col:

  Color for the center dots marking each (x, y) location. Defaults to
  `col`.

- point_pch, point_cex:

  Plotting character and size for the center dots. Set `point_pch = NA`
  to omit them.

- head_length:

  Numeric. Length of the arrowhead edges, in inches. Passed as `length`
  to [`arrows`](https://rdrr.io/r/graphics/arrows.html). Default `0.08`.

- head_angle:

  Numeric. Angle in degrees between the arrowhead edges and the shaft.
  Passed as `angle` to
  [`arrows`](https://rdrr.io/r/graphics/arrows.html). Default `25`.

- lwd:

  Line width for the arrows.

- add:

  Logical. If `TRUE`, add arrows to an existing plot instead of starting
  a new one (all plot-setup arguments below are then ignored). Default
  `FALSE`.

- asp:

  Numeric aspect ratio passed to
  [`plot`](https://rdrr.io/r/graphics/plot.default.html) when
  `add = FALSE`. Default `1`, so that a stimulus's direction is not
  visually distorted by unequal x/y scaling; set to `NA` to use the
  device default instead.

- xlab, ylab, xlim, ylim, main:

  Passed to [`plot`](https://rdrr.io/r/graphics/plot.default.html) when
  `add = FALSE`.

- ...:

  Further arguments passed to
  [`plot`](https://rdrr.io/r/graphics/plot.default.html) when
  `add = FALSE`.

## Value

Invisibly returns a data frame with columns `x`, `y`, `z` and the arrow
endpoints `x0`, `y0`, `x1`, `y1`. Called chiefly for its side effect of
drawing on the current graphics device.

## Examples

``` r
set.seed(1)
x <- rnorm(8)
y <- rnorm(8)
z <- seq(0, 315, by = 45)
plot_directions(x, y, z, length = 0.15, col = "steelblue")
```
