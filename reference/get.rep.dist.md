# Get representational distances

Given a list of embeddings, this function computes the procrustes
distance between each pair and returns this as a distance matrix.

## Usage

``` r
get.rep.dist(elist, metric = c("sqrt_ss", "corr_dist", "ss"))
```

## Arguments

- elist:

  List of embeddings.

- metric:

  Character. Which distance to compute from the Procrustes fit between
  each pair, one of:

  `"sqrt_ss"`

  :   (default) `sqrt(ss)`, the standard Procrustes distance used in the
      shape-analysis literature. Unlike `"corr_dist"` below, this
      corresponds to an actual Euclidean distance between the two
      optimally aligned (rotated, reflected, and scaled) configurations,
      so it is the recommended choice for distance-based methods like
      hierarchical clustering, k-medoids, or MDS.

  `"corr_dist"`

  :   `1 - sqrt(1 - ss)`, i.e. one minus the Procrustes "correlation"
      `sqrt(1 - ss)`. This was this function's only behavior before the
      `metric` argument was added (then selected via `rootflag = TRUE`);
      kept for backward compatibility and for contexts that specifically
      want "1 minus a correlation-like similarity" rather than a proper
      distance – it is not guaranteed to satisfy the triangle
      inequality.

  `"ss"`

  :   The raw normalized sum of squares (equivalently `sqrt_ss^2`), i.e.
      this behaves like a *squared* distance. Rank-based clustering
      methods (e.g. single/complete linkage) give identical results
      whether they're fed `"ss"` or `"sqrt_ss"`, since one is a
      monotonic transform of the other, but methods that use the actual
      metric values (Ward's linkage, k-medoids, MDS) should use
      `"sqrt_ss"` instead.

  This argument replaces the previous `rootflag` argument
  (`rootflag = TRUE` corresponded to `metric = "corr_dist"`, and
  `rootflag = FALSE` to `metric = "ss"`).

## Value

A matrix of distances between each pair of embeddings.

## Details

Each element of the list should contain a matrix of embedding
coordinates from one participant. Each embedding should contain the same
items in the same order, and should be of the same dimension.

All three metrics are computed from `ss`, the normalized sum of squares
from a symmetric Procrustes alignment (rotation, reflection, and
scaling) between each pair, and are already bounded in \\\[0,1\]\\ – no
further normalization is needed before using them for clustering.

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
#>            [,1]       [,2]      [,3]
#> [1,] 0.00000000 0.01843194 0.7863975
#> [2,] 0.01843194 0.00000000 0.7870027
#> [3,] 0.78639752 0.78700268 0.0000000

#Cluster participants using the recommended default metric:
hclust(as.dist(sdist), method = "ward.D")
#> 
#> Call:
#> hclust(d = as.dist(sdist), method = "ward.D")
#> 
#> Cluster method   : ward.D 
#> Number of objects: 3 
#> 
```
