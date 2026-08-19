# Spectral similarity between two matrices' variance structure

Computes the cosine similarity between the singular-value spectra of two
matrices, as a rotation-independent proxy for how similar their variance
structure is.

## Usage

``` r
procrustes_spectral_ceiling(candidate, target)
```

## Arguments

- candidate:

  Numeric matrix, rows = items, columns = dimensions.

- target:

  Numeric matrix, rows = items, columns = dimensions. `candidate` and
  `target` need not have the same number of columns.

## Value

A single number between 0 and 1: the cosine similarity between the
(zero-padded) singular value vectors of `candidate` and `target`.

## Details

Each matrix is column-centered and its singular values extracted via
SVD. The shorter singular-value vector is zero-padded to match the
length of the longer one, and the cosine similarity between the two
vectors is returned.

Because this compares only the spectra (not the aligned coordinates
themselves), it does not require `candidate` and `target` to share the
same dimensionality or item ordering alignment the way an actual
Procrustes fit (e.g.
[`get.rep.dist`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md))
does — it asks only whether the two embeddings distribute variance
across dimensions in a similar way. A value near 1 means the two
matrices have a similarly shaped variance profile (e.g. both dominated
by one or two dimensions); it does not by itself mean the embeddings are
otherwise similar.

## Examples

``` r
set.seed(1)
# Two matrices with similarly shaped (but not identical) spectra
candidate <- cbind(rnorm(20, sd = 4), rnorm(20, sd = 1))
target    <- cbind(rnorm(20, sd = 5), rnorm(20, sd = 1.2), rnorm(20, sd = 0.1))
procrustes_spectral_ceiling(candidate, target)
#> [1] 0.9976535
```
