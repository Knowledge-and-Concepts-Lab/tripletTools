# Get representational distances

Given a list of embeddings, this function computes the procrustes
distance between each pair and returns this as a distance matrix.

## Usage

``` r
get.rep.dist(elist, rootflag = TRUE)
```

## Arguments

- elist:

  List of embeddings.

- rootflag:

  Computer square root of distance? Defaults to TRUE

## Value

A matrix of distances between each pair of embeddings.

## Details

Each element of the list should contain a matrix of embedding
coordinates from one participant. Each embedding should contain the same
items in the same order, and should be of the same dimension.

By default the distance metric is the procrustes equivalent of Pearon's
correlation, that is `1 - sqrt(1 - ss)` where `ss` is the normalized sum
of squares from the aligned embeddings. If `rootflag=FALSE`, the
normalized sum of squares is used as the distance metric.

## Examples

``` r
#Subject 1 data
s1 <- matrix(
      c(1,1,
      2,2,
      3,3,
      4,4,
      5,5), 5,2,byrow = TRUE)

#Subject 2 is noisy version of subject 1
s2 <- s1 + runif(10) / 10

#Subject 3 is different:
s3 <- matrix(
      c(1,2,
      3,4,
      4,3,
      2,1,
      5,2), 5,2,byrow = TRUE)

slist <- list(s1,s2,s3)

sdist <- get.rep.dist(slist)

head(sdist)
#>              [,1]         [,2]      [,3]
#> [1,] 0.000000e+00 7.250482e-05 0.3822792
#> [2,] 7.250482e-05 0.000000e+00 0.3772223
#> [3,] 3.822792e-01 3.772223e-01 0.0000000
```
