# Effective (numerical) rank of a matrix

Computes the numerical rank of a matrix after centering its columns, by
counting singular values that exceed a machine-precision-scaled
tolerance.

## Usage

``` r
matrix_rank(M)
```

## Arguments

- M:

  Numeric matrix (or object coercible to one), rows = items, columns =
  dimensions.

## Value

Integer giving the number of singular values of the centered matrix that
exceed the tolerance
`max(dim(M)) * max(singular values) * .Machine$double.eps`.

## Details

`M` is column-centered before computing its singular value
decomposition, so the returned rank reflects variance structure rather
than an offset from the origin. This is useful for checking how many
dimensions of an embedding actually carry signal — for example, an
embedding fit with `d = 8` dimensions may have an effective rank of only
4 if four dimensions are numerically flat.

## Examples

``` r
# A matrix with two genuinely independent columns and a third that is a
# linear combination of the first two has rank 2, not 3.
set.seed(1)
a <- rnorm(20)
b <- rnorm(20)
M <- cbind(a, b, 2 * a - b)
matrix_rank(M)
#> [1] 2
```
