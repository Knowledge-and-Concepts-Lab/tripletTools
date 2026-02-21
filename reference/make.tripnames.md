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
trips <- cfd_triplets[[10]] #Triplet data for participant 10
tnames <- make.tripnames(trips) #Make triplet names
tnames[1:5] #Names of first five triplets
#> [1] "CFD-WF-026-008-A_CFD-WM-023-012-A_CFD-WM-033-014-A"   
#> [2] "CFD-BM-002-016-A_CFD-WM-023-012-A_CFD-WM-038-011-A"   
#> [3] "CFD-BM-038-007-HO_CFD-BF-002-004-HO_CFD-BF-050-004-HO"
#> [4] "CFD-WM-038-018-F_CFD-WF-020-027-F_CFD-WF-026-024-F"   
#> [5] "CFD-BM-002-002-F_CFD-BM-009-008-A_CFD-BM-038-007-HO"  
```
