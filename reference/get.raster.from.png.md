# Get raster from PNG

This function reads a PNG file and converts it to a raster object with a
transparent background for plotting.

## Usage

``` r
get.raster.from.png(f)
```

## Arguments

- f:

  Filename for PNG image.

## Details

When plotting line-drawings as points on a scatterplot (using
`plot_pics` for instance), it can be useful to keep the line drawing
background transparent and to be able to control the color in which the
image is plotted. Converting PNGs to rasters allows this functionality.
This function converts the PNG to a raster object; setting the `pc`
argument in `plot_pics` then controls the color when plotting the image.
