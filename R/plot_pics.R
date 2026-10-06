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
#' @param psize Each image's height, as a proportion of the plotting
#'  surface's physical height. Width is derived from the image's own
#'  native pixel aspect ratio, so images are never stretched to match the
#'  plotting surface's aspect ratio (see Details).
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
#' Each image is drawn with its own native pixel aspect ratio (width/height,
#' from its `dim()`), not the plotting surface's aspect ratio. `psize` only
#' sets the physical height of each image (as a proportion of the plotting
#' region's physical height); the width is derived from that image's own
#' aspect ratio. Without this, a non-square plotting device/window (or a
#' mix of portrait and landscape images) would silently stretch every
#' image to fill a box shaped like the plot window, distorting it.
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
#' emb <- icon_emb_ind[[1]] #Get embedding from first participant
#'
#' plot_pics(emb, icon_pics, psize = 0.03)
#'
#' #Plot the same data as a hierarchical cluster plot with images as leaves.
#' hc <- stats::hclust(dist(emb), method = "ward.D")
#' pt <- ape::as.phylo(hc)
#'
#' plot(pt, type = "fan", show.tip.label=FALSE)
#' tip_coords <- get.tip.coords()
#' plot_pics(tip_coords, icon_pics, newplot = FALSE)



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

  #Get ranges on axes and the plotting region's physical size (inches) --
  #both are needed (not just the axis ranges) to size each image box so it
  #comes out with the correct *physical* aspect ratio regardless of
  #whether the plotting surface itself is square (see compute_pic_halfsize())
  xlim <- par('usr')[1:2]
  ylim <- par('usr')[3:4]
  pin  <- par('pin')

  #Main plotting loop
  for (i1 in c(sitems)) {
    currpic <- plist[[i1]]
    if (!is.null(pc)){
      currpic[currpic == rgb(0, 0, 0,1)] <- pc[i1]
    }

    #Native pixel aspect ratio (width / height) of this image, so it's
    #plotted at its own shape rather than stretched to the plot window's.
    img_dim <- dim(currpic)
    native_ar <- img_dim[2] / img_dim[1]

    sz <- compute_pic_halfsize(native_ar, psize, pin, xlim, ylim)

    graphics::rasterImage(currpic, md[i1, x] - sz[["xsz"]], md[i1, y] - sz[["ysz"]],
              md[i1, x] + sz[["xsz"]], md[i1, y] + sz[["ysz"]])
  }
}

# Half-width/half-height (in data units) of the box used to plot one image
# via rasterImage(), sized so the image keeps its own native pixel aspect
# ratio (native_ar = width/height) regardless of the plotting surface's
# aspect ratio. psize sets the image's physical height as a proportion of
# the plotting region's physical height (pin[2]); width is derived from
# native_ar and the actual data-units-per-inch conversion in each
# direction (which depends on both pin and the axis ranges), so the result
# is correct whether or not the plot region (pin) or its data ranges
# (xlim/ylim) are themselves square. Takes pin/xlim/ylim as arguments
# (rather than reading par() itself) so it's testable without a live
# graphics device.
compute_pic_halfsize <- function(native_ar, psize, pin, xlim, ylim) {
  xrange <- max(xlim) - min(xlim)
  yrange <- max(ylim) - min(ylim)

  ysz <- psize * yrange
  xsz <- ysz * native_ar * (xrange * pin[2]) / (yrange * pin[1])

  c(xsz = xsz, ysz = ysz)
}
