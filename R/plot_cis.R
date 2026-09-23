#' Plot column means and 95% confidence intervals
#'
#' Computes the mean and a 95% confidence interval (via \code{\link[stats]{t.test}})
#' for each column of a numeric matrix, then plots them either as a line-and-ribbon
#' plot (default) or as a barplot with error bars.
#'
#' @param d A numeric matrix (or object coercible to one, e.g. a data frame of
#'   numeric columns) with more than one row. Each column is treated as one
#'   group/condition/item to summarize; each row is one observation (e.g. one
#'   participant). Column names, if present, are copied to the returned
#'   summary matrix.
#' @param barflag Logical. If \code{TRUE}, plot a barplot with error bars via
#'   \code{\link[graphics]{barplot}}. If \code{FALSE} (default), plot a line
#'   for the column means with a transparent ribbon for the confidence
#'   interval.
#' @param newflag Logical, default \code{TRUE}. Only used when
#'   \code{barflag = FALSE}: whether to start a new plot (\code{TRUE}) or add
#'   the line/ribbon to the current plot (\code{FALSE}), e.g. to overlay a
#'   second condition on an existing ribbon plot. \strong{Has no effect when
#'   \code{barflag = TRUE}} -- \code{\link[graphics]{barplot}} always starts a
#'   new plot.
#' @param xvals Numeric vector of x-axis positions for each column, or
#'   \code{NULL} (default) to use \code{1:ncol(d)}. Must have length equal to
#'   \code{ncol(d)}. \strong{Only used when \code{barflag = FALSE}} -- bar
#'   positions in barplot mode come from \code{\link[graphics]{barplot}}
#'   itself and do not depend on \code{xvals}.
#' @param rgbvec Numeric vector of length 3, the red/green/blue proportions
#'   (each in \code{[0, 1]}) used for the mean line and ribbon fill. Default
#'   \code{c(0, 0, 1)} (blue). \strong{Only used when \code{barflag = FALSE}}
#'   -- bar colors in barplot mode follow \code{\link[graphics]{barplot}}'s
#'   own defaults (or \code{col}, passed via \code{...}).
#' @param capfrac Numeric in \code{(0, 1]}, default \code{0.8}. Only used
#'   when \code{barflag = TRUE}: the width of each error bar's horizontal cap
#'   (the flat top/bottom of the "I"-beam drawn by
#'   \code{\link[graphics]{arrows}}), as a fraction of that bar's own width --
#'   so caps stay proportional to the bars regardless of how many bars there
#'   are or how wide the plot is. See \emph{Details} for why this replaced an
#'   earlier, unit-inconsistent computation.
#' @param ... Additional graphical parameters passed through to
#'   \code{\link[graphics]{barplot}} (when \code{barflag = TRUE}) or to
#'   \code{\link[graphics]{plot}} (when \code{barflag = FALSE} and
#'   \code{newflag = TRUE}) -- e.g. \code{col}, \code{ylim}, \code{main},
#'   \code{xlab}/\code{ylab}, or (for the barplot case) \code{width} to
#'   change the bars' own width from the default of 1.
#'
#' @return Invisibly returns a 3-row numeric matrix with row names
#'   \code{"mean"}, \code{"upperci"}, \code{"lowerci"} and one column per
#'   column of \code{d} (column names copied from \code{d} if present).
#'
#' @details
#' For each column, missing values (\code{NA}) are dropped before computing
#' the mean and confidence interval. A column with zero remaining values
#' returns \code{NA} for all three summary rows. A column with exactly one
#' remaining value, or zero variance, has no well-defined confidence interval
#' -- \code{"upperci"}/\code{"lowerci"} are both set equal to \code{"mean"}
#' in that case (a zero-width interval), rather than \code{NA}, so the point
#' still plots even though there's nothing meaningful to say about its
#' uncertainty. Treat a zero-width interval in the output as "not enough data
#' to estimate a CI," not as genuine certainty.
#'
#' \strong{Why \code{capfrac} instead of a fixed \code{length} passed to
#' \code{\link[graphics]{arrows}}:} an earlier version of this function
#' computed the error-bar cap width as a fraction of the *data* range
#' (bar spacing relative to the total x-axis range) and passed that number
#' directly as \code{arrows(..., length = )}, which \pkg{graphics} interprets
#' in \strong{inches}, not as a fraction of anything data-related. Those two
#' quantities are unrelated units, so the resulting cap width scaled
#' incorrectly with the number of bars -- with only a few, widely-spaced
#' bars, the old formula could produce caps several inches wide. This version
#' instead computes the desired cap width in data coordinates directly (as
#' \code{capfrac} of the actual bar width, using \code{width} from \code{...}
#' if supplied, matching \code{\link[graphics]{barplot}}'s own default of 1
#' otherwise) and converts *that* to inches using the plot's actual
#' data-to-device scale (\code{par("pin")}/\code{par("usr")}), so the cap
#' stays a consistent, correctly-scaled fraction of each bar regardless of
#' bar count or plot size.
#'
#' @importFrom graphics lines polygon barplot box arrows par plot
#' @importFrom grDevices rgb
#' @importFrom stats t.test var
#'
#' @export
#'
#' @examples
#' x <- matrix(1:12, 3, 4)
#' plot_cis(x)
#'
#' # As a barplot, with narrower error-bar caps
#' plot_cis(x, barflag = TRUE, capfrac = 0.5)
plot_cis <- function(
    d, barflag = FALSE,
    newflag = TRUE,
    xvals = NULL,
    rgbvec = c(0, 0, 1),
    capfrac = 0.8,
    ...) {

  ### Check arguments
  #Check that d is a numeric matrix
  d <- try({
    d <- as.matrix(d)
    if (!is.numeric(d)) stop("Not a numeric matrix")
    d
  }, silent = TRUE)

  # Check if the coercion was successful
  if (inherits(d, "try-error")) {
    stop("Error: Input must be a numeric matrix or coercible to one.")
  }

  #Number of items
  nitems <- dim(d)[2]

  #If xvals specified, check length is correct
  if(!is.null(xvals) & length(xvals) != nitems){
    stop("Number of xvalues does not match number of columns.")
  }

  #Check there are multiple rows:
  if(dim(d)[1] <=1) stop("Matrix must include more than one row")

  #Check capfrac is a valid fraction
  if (capfrac <= 0 || capfrac > 1) stop("capfrac must be in (0, 1].")

  ### Compute mean and confidence intervals for each column
  #Initialize output matrix
  o <- matrix(0,3,nitems)
  row.names(o) <- c("mean", "upperci", "lowerci")
  #Copy column names if they exist
  if(!is.null(colnames(d))) colnames(o) <- colnames(d)

  for(i1 in c(1:nitems)){
    vals <- d[, i1]
    vals <- vals[!is.na(vals)]
    if(length(vals) == 0){
      o[, i1] <- NA
    } else if(length(vals) == 1 || stats::var(vals) == 0){
      o[, i1] <- mean(vals)
    } else{
      t <- stats::t.test(vals)
      o[1, i1] <- t$estimate
      o[2:3, i1] <- t$conf.int[1:2]
    }
  }

  #Use indices for x values if they are not specified
  if(is.null(xvals)) xvals <- c(1:nitems)

  #Set xlim
  xlim <- range(xvals)

  ## Generate the plot
  #If a barplot is indicated
  if(barflag){
    x <- barplot(o[1,], xpd=FALSE, las = 2, ...) #barplot

    # Cap width in data coordinates: capfrac of the actual bar width (from
    # `width` in ..., defaulting to barplot()'s own default of 1), then
    # converted to inches via the plot's real data-to-device scale -- see
    # @details for why this replaced a unit-inconsistent computation.
    dots <- list(...)
    bar_width_data <- if (!is.null(dots$width)) dots$width[1] else 1
    usr <- graphics::par("usr")
    pin <- graphics::par("pin")
    inches_per_xunit <- pin[1] / (usr[2] - usr[1])
    bwid <- (capfrac * bar_width_data / 2) * inches_per_xunit

    #error bars:
    graphics::arrows(x0=x, y0 = o[2,], x1 = x, y1 = o[3,],
                     angle = 90, length = bwid, code = 3)
    box() #box
  } else{ #Otherwise a ribbon plot:

    #Start new plot if newflag is set
    if(newflag){
      plot(0,0, type = "n", xlim=xlim, ...)
    }

    #Add line for mean
    graphics::lines(xvals, o[1,], type = "o", pch=16, lwd=2,
                    col = grDevices::rgb(rgbvec[1], rgbvec[2],rgbvec[3]))
    #Add transparent ribbon for confidence interval
    graphics::polygon(c(xvals, xvals[nitems:1]), c(o[2,], o[3,nitems:1]),
                      col=grDevices::rgb(rgbvec[1], rgbvec[2],rgbvec[3], 0.2),
                      border=NA)
  }
  invisible(o)
}
