#' Plot pictures in a scatterplot
#'
#' This function plots a list of PNG or raster images as the points in a scatterplot.
#'
#' @importFrom stats runif
#' @importFrom graphics par
#'
#' @param md Matrix of data indicating where each image is to be plotted.
#' @param plist List of PNG or raster images
#' @param x Which column of the matrix should be used for x-axis position
#' @param y Which column of the matrix should be used for y-axis position
#' @param pr Proportion of items to be plotted OR vector indicating which
#'  items should be plotted.
#' @param pc If images are rasters, what color should they be plotted in?
#' @param psize Plot size for each image as proportion of plotting surface
#' @param newplot Should a new plot be generated? If FALSE images added to
#'  current plot.
#' @param ...  Other graphical parameters
#'
#' @returns Generates a plot or adds images to existing plot.
#'
#' @details
#' The number of rows in the data matrix must be equal to the length of the list
#' containing the images to be plotted. Each row corresponds to one image; thus
#' the first image in the list will be plotted at the coordinates in row 1 of
#' the data matrix.
#'
#' When `newplot=FALSE` the images will be added as points to the existing plot.
#' When used with `get.tip.coords` this can add images to the tips of phylogram
#' plots, an effective way to visualize structure in embeddings with more than
#' two or three dimensions.
#'
#' When there are many images, they often clutter the plot, making it hard to see
#' structure. You can control the proportion of images shown by setting `pr` to a
#' value smaller than 1.0. In this case, a random sample of impages will be plotted.
#'
#' If images are line-drawings and are loaded as rasters rather than PNGs, setting
#' the plot color `pc` will control the color the image is displayed in. This can
#' be specified as a single value for all images or as a vector of colors; if a vector
#' each element sets the plot color for one image. This can be useful for displaying
#' other data in the plot, such as the gender of the participant who produced the
#' drawing.
#'
#' @export
#'
#' @examples
#' #Plot a 2D embedding as a scatterplot using images instead of points:
#'
#' emb <- cfd_embeddings[[1]] #Get embedding from first participant
#'
#' plot_pics(emb, cfd_pics, psize = 0.03)
#'
#' #Plot the same data as a hierarchical cluster plot with images as leaves.
#' hc <- stats::hclust(dist(emb), method = "ward.D")
#' pt <- ape::as.phylo(hc)
#'
#' plot(pt, type = "fan", show.tip.label=FALSE)
#' tip_coords <- get.tip.coords()
#' plot_pics(tip_coords, cfd_pics, newplot = FALSE)



plot_pics <- function (md, plist, x = 1, y = 2, pr = 1.0, pc = NULL,
                       psize = .05, newplot=TRUE, ...)
{
  ## Set variable and check arguments
  args <- list(...) #Capture arguments
  nitems <- dim(md)[1] #Number of items

  #Check that picture list and plotting data have same number of items
  if (nitems != length(plist))
    stop("Matrix row number and picture list length don't match")

  #Select items to be plotted
  if (length(pr)==1){
    sitems <- c(1:nitems)[stats::runif(nitems) <= pr]
    } else sitems <- pr

  #Set plotting color if specified
  if (!is.null(pc) & length(pc) == 1) {
    pc <- rep(pc, times = nitems)
  }
  else if (!is.null(pc) & length(pc) != nitems) {
    stop("Number of colors does not equal number of items")
  }

  ##Generate plot
  #Generate the plotting frame if it's a new plot
  if(newplot){

    graphics::plot.default(0, 0, type = "n", ...)

    }

    # Call plot.default deterministically
    dots$type <- "n"
    do.call(graphics::plot.default, c(list(x = 0, y = 0), dots))

  }

  #Get ranges on axes
  xlim <- par('usr')[1:2]
  ylim <- par('usr')[3:4]

  #Set size of each image
  xsz <- psize * (max(xlim) - min(xlim))
  ysz <- psize * (max(ylim) - min(ylim))


  #Main plotting loop
  for (i1 in c(sitems)) {
    currpic <- plist[[i1]]
    if (!is.null(pc)){
      currpic[currpic == rgb(0, 0, 0,1)] <- pc[i1]
    }
      graphics::rasterImage(currpic, md[i1, x] - xsz, md[i1, y] - ysz,
                md[i1, x] + xsz, md[i1, y] + ysz)
  }
}
