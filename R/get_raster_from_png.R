#' Get raster from PNG
#'
#' This function reads a PNG file and converts it to a raster object with
#' a transparent background for plotting.
#'
#' @param f Filename for PNG image.
#'
#' @details
#' When plotting line-drawings as points on a scatterplot (using
#' `plot_pics` for instance), it can be useful to keep the line drawing
#' background transparent and to be able to control the color in which
#' the image is plotted. Converting PNGs to rasters allows this functionality.
#' This function converts the PNG to a raster object; setting the `pc`
#' argument in `plot_pics` then controls the color when plotting the image.

get.raster.from.png <- function(f){

  thispng <- png::readPNG(f) #Reads the png
  if(length(dim(thispng)) ==3) thispng <- thispng[,,1] #Reduce to 2D if 3D
  v <- dim(thispng)[1] #Vertical dimension
  h <- dim(thispng)[2] #horizontal dimension
  o <- matrix(rgb(0,0,0,0), v, h) #Fully transparent raster matrix of same dimension
  o[thispng != 1] <- rgb(0,0,0,1) #Opaque values wherever original image is non-white
  o #return raster output
}
