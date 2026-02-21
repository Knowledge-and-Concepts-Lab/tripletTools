#' Plot column means and confidence intervals
#'
#'
#' @importFrom graphics lines polygon barplot box
#' @importFrom grDevices rgb
#'
#' @param d A matrix of numerical data
#' @param barflag Flag indicating whether a barplot is desired
#' @param xvals Vector of x values equal in length to number of columns in d
#' @param newflag Should new plot be generated, default T
#' @param rgbvec Vector of red, green, blue proportions
#' @param ... Other graphical parameters
#'
#' @return Invisibly returns matrix of column means and 95% confidence intervals
#'
#' @details
#' This function computes the mean and 95% confidence intervals of each column
#' in `d` and plots these either as a line plot with a transparent ribbon
#' (default) or as a barplot.
#'
#'
#' @export
#'
#' @examples
#' x <- matrix(c(1:12),3,4)
#' plot_cis(x)

plot_cis <- function(
    d, barflag=FALSE,
    newflag = TRUE,
    xvals=NULL,
    rgbvec = c(0,0,1),
    ...){

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
  if(dim(d)[1] <=1) stop("Matrix mmust include more than one row")

  ### Compute mean and confidence intervals for each column
  #Initialize output matrix
  o <- matrix(0,3,nitems)
  row.names(o) <- c("mean", "upperci", "lowerci")
  #Copy column names if they exist
  if(!is.null(colnames(d))) colnames(o) <- colnames(d)

  for(i1 in c(1:nitems)){
    #If numbers are constant:
    if(stats::var(d[,i1])==0){
      o[,i1] <- mean(d[,i1])
      } else{
      #Otherwise compute mean and CI
      t <- stats::t.test(d[,i1])
      o[1,i1] <- t$estimate
      o[2:3,i1] <- t$conf.int[1:2]
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

    bwid <- 1.5 * (x[2] - x[1])/(par("usr")[2] - par("usr")[1])

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
