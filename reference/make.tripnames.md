# Make triplet names

This function creates a unique name for each triplet appearing in a
triplet data frame.

## Usage

``` r
make.tripnames(tripdat)
```

## Arguments

- tripdat:

  A data frame containing triplet data; must conform to naming
  conventions.

## Value

A character vector containing the unique triplet name for each trial in
the triplet dataframe.

## Details

This function is useful for finding responses to a given triplet, which
is especially important when computing within and between-participant
consistency on validation trials.

## Examples

``` r
trips <- icon_triplets[[1]] #Triplet data for participant 1
tnames <- make.tripnames(trips) #Make triplet names
tnames[1:5] #Names of first five triplets
#> [1] "pnhns_pdcos_pncnb" "fnmyb_fdfob_pncnb" "pnhob_pdcos_pncnb"
#> [4] "pdcns_fnmob_fnmow" "pnhns_fnfob_fnfow"
```
