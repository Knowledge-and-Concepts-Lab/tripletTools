# From a list of same-shaped embeddings (e.g. smooth_embedding_trajectory()'s
# `embeddings`), find the maximal range for each dimension across all of
# them -- used by plot_2d_trajectory()/plot_3d_trajectory() to keep axis
# limits fixed across every frame, rather than rescaling from one query
# point to the next.
# na.rm = TRUE matters here specifically because smooth_embedding_trajectory()
# can legitimately return an all-NA embedding for a query point with no
# meaningful kernel weight (see its own docs) -- without na.rm, one such
# point would poison every axis's range to NA.
get_axis_ranges <- function(elist) {
  ndims <- dim(elist[[1]])[2]
  rngs <- vector("list", ndims)
  for (i in seq_len(ndims)) {
    per_embedding <- t(vapply(elist, function(e) range(e[, i], na.rm = TRUE), numeric(2)))
    rngs[[i]] <- c(min(per_embedding[, 1], na.rm = TRUE), max(per_embedding[, 2], na.rm = TRUE))
  }
  names(rngs) <- paste0("d", seq_len(ndims))
  rngs
}

# Shared by plot_2d_trajectory()/plot_3d_trajectory(): checks that loc is a
# valid integer index into traj$query_points, with one clear error message
# for both (rather than two copies that could drift).
validate_traj_loc <- function(traj, loc) {
  n_query <- length(traj$query_points)
  if (loc < 1 || loc > n_query || loc != round(loc)) {
    stop(sprintf("loc must be an integer between 1 and %d (length(traj$query_points)).", n_query))
  }
}

# Add a density/weight strip to the bottom margin of the *current* plot,
# spanning a given x-range (in that plot's own rendered coordinate system,
# i.e. whatever stats::par("usr")[1:2] means for the plot already on the
# device). Shared by plot_2d_trajectory() directly and by
# add_density_to_cube() (which first has to work out what that x-range even
# is for a scatterplot3d cube -- see its own comment).
add_density_strip <- function(xlim, density, gap = 0.02, height = 0.10,
                               downward = TRUE, ...) {
  xx <- seq(xlim[1], xlim[2], length.out = length(density))

  usr <- graphics::par("usr")
  yrange <- diff(usr[3:4])
  baseline <- usr[3] - gap * yrange

  dmax <- max(density, na.rm = TRUE)
  hh <- if (dmax > 0) density / dmax * height * yrange else rep(0, length(density))

  y1 <- if (downward) baseline - hh else baseline + hh

  graphics::segments(x0 = xx, y0 = baseline, x1 = xx, y1 = y1, xpd = TRUE, ...)

  invisible(list(x = xx, baseline = baseline, heights = hh, xlim = xlim))
}

# Add a density/weight strip to the bottom margin of a scatterplot3d plot.
#
# scatterplot3d() doesn't expose where its rendered 3-D cube actually lands
# in 2-D plot coordinates (it depends on the current `angle` and axis
# ranges), so there's no public API for "draw something aligned with the
# cube's floor." This reaches into xyz.convert()'s own closure environment
# to read the internal variables scatterplot3d() uses for its own
# projection math (x.min/x.max/y.max/yx.f), reconstructs the floor's
# rendered horizontal extent from them, then delegates to
# add_density_strip() for the actual drawing.
#
# This is inherently fragile: it depends on scatterplot3d's internal
# implementation, not a documented public interface, and would break if a
# future version of the package renamed or restructured those internals.
# There is no clean alternative given what scatterplot3d exposes -- flagged
# here for whoever next needs to touch this.
add_density_to_cube <- function(s3d, density, gap = 0.02, height = 0.10,
                                 downward = TRUE, ...) {
  e <- environment(s3d$xyz.convert)

  x.min <- get("x.min", envir = e)
  x.max <- get("x.max", envir = e)
  y.max <- get("y.max", envir = e)
  yx.f  <- get("yx.f",  envir = e)

  cube.x <- c(x.min, x.max, x.min + y.max * yx.f, x.max + y.max * yx.f)
  add_density_strip(c(min(cube.x), max(cube.x)), density, gap, height, downward, ...)
}

# Shared by plot_2d_trajectory()/plot_3d_trajectory(): draws the red
# "current query point" marker and (if pos is supplied) small black dots
# for each participant's own position, both anchored to an already-drawn
# density strip (the return value of add_density_strip()/
# add_density_to_cube()).
add_trajectory_markers <- function(d, traj, pos, loc) {
  graphics::segments(d$x[loc], d$baseline, d$x[loc], d$baseline - d$heights[loc] * 1.1,
                      col = 2, lwd = 4, xpd = TRUE)

  if (!is.null(pos)) {
    # Defensive coercion: cmdscale() (a very common source of `pos`) always
    # returns a matrix, even for k = 1 -- confirmed to be an easy mistake to
    # make (it does not itself break the position math, verified directly,
    # but it's a real foot-gun worth guarding against rather than silently
    # tolerating). drop() collapses a 1-row or 1-column matrix to a plain
    # vector and leaves an already-plain vector untouched; a genuine
    # multi-column matrix (a different, more serious mistake -- e.g.
    # accidentally passing a multi-dimensional embedding instead of a 1-D
    # position) is caught explicitly rather than silently misread.
    pos <- drop(as.matrix(pos))
    if (is.matrix(pos)) {
      stop("pos must be a 1-D numeric vector (or a matrix with exactly one row or column) giving each participant's single scalar position along the trajectory axis -- got a matrix with dimensions ",
           paste(dim(pos), collapse = " x "), ".")
    }

    qr <- range(traj$query_points)
    frac <- (pos - qr[1]) / diff(qr)
    pos_x <- d$xlim[1] + frac * diff(d$xlim)
    # cex/pch chosen to actually be visible against the gray density strip
    # at realistic plot sizes -- confirmed empirically that the strip's own
    # tick-mark-like bars make small, thin markers easy to miss even when
    # correctly positioned and already drawn on top (not a z-order issue).
    graphics::points(pos_x, rep(d$baseline, length(pos_x)), pch = 19, cex = 1.1,
                      col = "black", xpd = TRUE)
  }
}

#' Plot a 3-D embedding at one point along a smoothed trajectory
#'
#' Draws a 3-D scatterplot of the kernel-weighted embedding at one query
#' point of a \code{\link{smooth_embedding_trajectory}} result, with a
#' density-style strip along the bottom of the plot showing
#' \code{effective_n} across every query point, a red marker at the query
#' point currently shown, and (optionally) small black dots marking real
#' participants' own positions along the same axis -- so a sequence of
#' calls at increasing \code{loc} (e.g. to build an animation, as in
#' \code{gifski::save_gif()}) can be read both as "what the representation
#' looks like here" and "how much real data actually supports this point."
#' \code{\link{plot_2d_trajectory}} is the 2-D equivalent, built on base
#' graphics instead of \pkg{scatterplot3d}, with the same argument
#' conventions.
#'
#' @param traj The full return value of
#'   \code{\link{smooth_embedding_trajectory}} (a list with
#'   \code{query_points}, \code{embeddings}, \code{effective_n}, among
#'   others). Each embedding must have exactly 3 columns.
#' @param pos Numeric vector or \code{NULL}. Participants' own positions
#'   along the same 1-D axis \code{traj} was built from (e.g. the same
#'   \code{positions} passed to \code{\link{smooth_embedding_trajectory}}).
#'   When supplied, each one is drawn as a small black dot along the
#'   bottom density strip, at the position implied by linearly mapping
#'   \code{range(traj$query_points)} onto the strip's rendered extent --
#'   this assumes \code{traj$query_points} are evenly spaced (the default
#'   when \code{\link{smooth_embedding_trajectory}} generates its own grid)
#'   and is only an approximation otherwise. A position outside
#'   \code{range(traj$query_points)} is still plotted, which can place it
#'   outside the visible plot area. Default \code{NULL} omits the dots.
#' @param loc Integer index into \code{traj$query_points}/\code{traj$embeddings}
#'   -- which query point to display. Must be between 1 and
#'   \code{length(traj$query_points)}.
#' @param pcols,bcols Point fill/border colors, recycled across items as
#'   usual (see \code{\link[scatterplot3d]{scatterplot3d}}'s \code{bg}/
#'   \code{color}). Default \code{NULL} for both uses plain black for
#'   every item.
#' @param pch Point character. Default \code{NULL} uses \code{21} (a
#'   filled circle with a separately-colorable border, matching the
#'   \code{pcols}/\code{bcols} split).
#' @param cex.symbols Point size. Default \code{1}.
#' @param ... Additional arguments passed to
#'   \code{\link[scatterplot3d]{scatterplot3d}}, overriding this
#'   function's own defaults for any name also used internally (e.g.
#'   \code{angle}, \code{grid}, \code{box}) -- see \emph{Overriding plot
#'   appearance} below.
#'
#' @section Overriding plot appearance:
#' \code{pcols}/\code{bcols}/\code{pch}/\code{cex.symbols} are kept as
#' their own named arguments because each has specific \code{NULL}-default
#' handling (e.g. recycling a single black color across every item).
#' Everything else \code{\link[scatterplot3d]{scatterplot3d}} accepts can
#' be set or overridden through \code{...} -- internally, a list of this
#' function's own defaults (\code{angle}, \code{mar}, axis limits, tick
#' marks, etc.) is merged with \code{list(...)} via
#' \code{\link[utils]{modifyList}} (so \code{...} values win on any
#' name clash) and passed to \code{scatterplot3d::scatterplot3d} via
#' \code{\link[base]{do.call}} -- so e.g. \code{angle = 60} or
#' \code{grid = FALSE} can be passed directly without this function
#' needing its own named argument for every possibility.
#'
#' @return The \code{scatterplot3d} object, returned invisibly (as
#'   \code{\link[scatterplot3d]{scatterplot3d}} itself returns it), in case
#'   the caller wants to add further elements to the same plot via its
#'   \code{$xyz.convert} coordinate-conversion function.
#'
#' @importFrom graphics par segments points
#' @importFrom utils modifyList
#'
#' @export
#'
#' @examples
#' \dontrun{
#' repdist <- get.rep.dist(icon_emb_ind)
#' pos <- cmdscale(repdist, k = 1)[, 1]
#' traj <- smooth_embedding_trajectory(icon_emb_ind, pos, n_query = 50)
#' plot_3d_trajectory(traj, pos = pos, loc = 25)
#' }
plot_3d_trajectory <- function(traj, pos = NULL, loc,
                                pcols = NULL, bcols = NULL, pch = NULL,
                                cex.symbols = 1, ...) {
  if (!requireNamespace("scatterplot3d", quietly = TRUE)) {
    stop("The 'scatterplot3d' package is required. Install it with install.packages('scatterplot3d').")
  }
  validate_traj_loc(traj, loc)
  if (ncol(traj$embeddings[[1]]) != 3) {
    stop("traj$embeddings must have exactly 3 columns -- plot_3d_trajectory() is for 3-D embeddings only.")
  }

  # Axis ranges symmetric around zero, fixed across every query point so a
  # sequence of calls at increasing loc doesn't rescale from frame to frame.
  rngs <- get_axis_ranges(traj$embeddings)
  xr <- c(-1, 1) * max(abs(rngs$d1))
  yr <- c(-1, 1) * max(abs(rngs$d2))
  zr <- c(-1, 1) * max(abs(rngs$d3))

  nitems <- nrow(traj$embeddings[[1]])
  if (is.null(pcols)) pcols <- rep("black", nitems)
  if (is.null(bcols)) bcols <- pcols
  if (is.null(pch)) pch <- 21

  tmp <- traj$embeddings[[loc]]
  default_args <- list(
    x = tmp[, 1], y = tmp[, 2], z = tmp[, 3],
    pch = pch, color = bcols, bg = pcols, cex.symbols = cex.symbols,
    label.tick.marks = FALSE, tick.marks = FALSE, angle = 45,
    xlab = "", ylab = "", zlab = "", mar = c(2, 1, 2, 1),
    xlim = xr, ylim = yr, zlim = zr
  )
  call_args <- utils::modifyList(default_args, list(...))
  p3d <- do.call(scatterplot3d::scatterplot3d, call_args)

  # Effective sample size strip along the bottom, red marker, and
  # participant-position dots.
  d <- add_density_to_cube(p3d, traj$effective_n, lwd = 2, col = "gray")
  add_trajectory_markers(d, traj, pos, loc)

  invisible(p3d)
}

#' Plot a 2-D embedding at one point along a smoothed trajectory
#'
#' The 2-D equivalent of \code{\link{plot_3d_trajectory}}, built on base
#' graphics (\code{\link[graphics]{plot}}) instead of \pkg{scatterplot3d},
#' with the same argument conventions: a density-style strip along the
#' bottom showing \code{effective_n} across every query point, a red
#' marker at the query point currently shown, and (optionally) small black
#' dots marking real participants' own positions along the same axis.
#'
#' @inheritParams plot_3d_trajectory
#' @param traj The full return value of
#'   \code{\link{smooth_embedding_trajectory}}. Each embedding must have
#'   exactly 2 columns (use \code{\link{plot_3d_trajectory}} for 3-D ones).
#' @param ... Additional arguments passed to \code{\link[graphics]{plot}},
#'   overriding this function's own defaults for any name also used
#'   internally (e.g. \code{asp}, \code{main}) -- same mechanism as
#'   \code{\link{plot_3d_trajectory}}'s \code{...} (see its
#'   \emph{Overriding plot appearance} section): this function's own
#'   defaults are merged with \code{list(...)} via
#'   \code{\link[utils]{modifyList}} and dispatched via
#'   \code{\link[base]{do.call}}.
#'
#' @return \code{NULL}, invisibly (\code{\link[graphics]{plot}} itself
#'   returns nothing meaningful to pass along).
#'
#' @importFrom graphics par segments points plot
#' @importFrom utils modifyList
#'
#' @export
#'
#' @examples
#' \dontrun{
#' repdist <- get.rep.dist(icon_emb_ind)
#' pos <- cmdscale(repdist, k = 1)[, 1]
#' traj <- smooth_embedding_trajectory(icon_emb_ind, pos, n_query = 50)
#' plot_2d_trajectory(traj, pos = pos, loc = 25)
#' }
plot_2d_trajectory <- function(traj, pos = NULL, loc,
                                pcols = NULL, bcols = NULL, pch = NULL,
                                cex.symbols = 1, ...) {
  validate_traj_loc(traj, loc)
  if (ncol(traj$embeddings[[1]]) != 2) {
    stop("traj$embeddings must have exactly 2 columns -- plot_2d_trajectory() is for 2-D embeddings only.")
  }

  rngs <- get_axis_ranges(traj$embeddings)
  xr <- c(-1, 1) * max(abs(rngs$d1))
  yr <- c(-1, 1) * max(abs(rngs$d2))

  nitems <- nrow(traj$embeddings[[1]])
  if (is.null(pcols)) pcols <- rep("black", nitems)
  if (is.null(bcols)) bcols <- pcols
  if (is.null(pch)) pch <- 21

  # A bit more room in the bottom margin than plot()'s own default leaves,
  # so the density strip (drawn via xpd = TRUE, i.e. clipped to the figure
  # region rather than the plot region) has somewhere to actually render,
  # not get clipped at the figure boundary. Restored on exit so this
  # doesn't leak into the caller's later plots.
  old_par <- graphics::par(mar = c(6, 4, 2, 2))
  on.exit(graphics::par(old_par), add = TRUE)

  tmp <- traj$embeddings[[loc]]
  default_args <- list(
    x = tmp[, 1], y = tmp[, 2],
    pch = pch, col = bcols, bg = pcols, cex = cex.symbols,
    xlab = "", ylab = "", xlim = xr, ylim = yr
  )
  call_args <- utils::modifyList(default_args, list(...))
  do.call(graphics::plot, call_args)

  # Effective sample size strip along the bottom, red marker, and
  # participant-position dots -- spanning the plot's own x-range, unlike
  # plot_3d_trajectory()'s cube-floor reconstruction, since a 2-D plot's
  # rendered x-extent is already exactly par("usr")[1:2].
  d <- add_density_strip(xr, traj$effective_n, lwd = 2, col = "gray")
  add_trajectory_markers(d, traj, pos, loc)

  invisible(NULL)
}
