# Variance captured by the top k dimensions of a target matrix

Computes the fraction of a matrix's total variance (sum of squared
singular values, after centering) that is captured by its top `k`
singular values.

## Usage

``` r
procrustes_rank_ceiling(target, k)
```

## Arguments

- target:

  Numeric matrix, rows = items, columns = dimensions.

- k:

  Number of leading dimensions to retain. Must be at least 1.

## Value

A single number between 0 and 1: the square root of the ratio of the
summed squared top-`k` singular values to the summed squared singular
values overall.

## Details

`target` is column-centered before computing its singular value
decomposition (matching how
[`vegan::procrustes`](https://vegandevs.github.io/vegan/reference/procrustes.html)
centers its inputs), and singular values that are numerically zero are
dropped before ranking. If `k` exceeds the number of nonzero singular
values, all of them are used.

This gives an upper bound — a "ceiling" — on how well a `k`-dimensional
embedding could ever recover `target`'s structure under a Procrustes
fit, independent of any particular candidate embedding: even a perfect
`k`-dimensional candidate cannot exceed this value, because it is a
property of `target` alone. Compare a real candidate embedding's
Procrustes correlation against this ceiling to judge how much of the
achievable structure it actually captures.

## Examples

``` r
set.seed(1)
# A target matrix whose variance is concentrated in its first two columns
target <- cbind(rnorm(20, sd = 5), rnorm(20, sd = 3), rnorm(20, sd = 0.1))
procrustes_rank_ceiling(target, k = 2)
#> [1] 0.9998981
```
