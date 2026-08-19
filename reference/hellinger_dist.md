# Pairwise Hellinger distances between rows of a profile matrix

Given a matrix of non-negative profiles (e.g. category membership
probabilities, or any set of values that can be normalized to sum to 1
within a row), computes the Hellinger distance between every pair of
rows.

## Usage

``` r
hellinger_dist(P)
```

## Arguments

- P:

  Numeric matrix (or object coercible to one) with non-negative entries,
  rows = items, columns = profile categories. Rows do not need to
  already sum to 1 — they are renormalized internally.

## Value

An object of class `"dist"` (as returned by
[`dist`](https://rdrr.io/r/stats/dist.html)) giving the Hellinger
distance between every pair of rows of `P`.

## Details

Rows are rescaled to sum to 1, and tiny negative values (numerical noise
from upstream computation) are clamped to zero before rescaling. The
Hellinger distance between two probability vectors \\p\\ and \\q\\ is
\\\frac{1}{\sqrt{2}} \lVert \sqrt{p} - \sqrt{q} \rVert_2\\, which is
bounded between 0 and 1 and, unlike KL divergence, is a proper metric
(symmetric and satisfies the triangle inequality).

## Examples

``` r
# Three items' membership probabilities across four categories
P <- matrix(
  c(0.7, 0.1, 0.1, 0.1,
    0.6, 0.2, 0.1, 0.1,
    0.1, 0.1, 0.1, 0.7),
  nrow = 3, byrow = TRUE
)
hellinger_dist(P)
#>           1         2
#> 2 0.1024918          
#> 3 0.5204323 0.4990536
```
