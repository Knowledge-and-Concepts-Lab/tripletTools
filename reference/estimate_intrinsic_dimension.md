# Estimate how many dimensions of a distance matrix reflect real structure

Given a participant-by-participant distance matrix (e.g. from
[`get.rep.dist`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md)),
estimates how many of its classical-MDS dimensions carry genuine
multivariate structure, as opposed to individual-level noise that
inflates every dimension's eigenvalue away from exactly zero without
necessarily reflecting any real, reproducible pattern. Used by
[`test_for_clusters`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md)
to choose `k_use` when it isn't supplied directly.

## Usage

``` r
estimate_intrinsic_dimension(
  dist_mat,
  n_permutations = 200,
  threshold_quantile = 0.95,
  seed = NULL,
  verbose = TRUE
)
```

## Arguments

- dist_mat:

  A participant-by-participant distance matrix (or a `dist` object),
  e.g. as returned by
  [`get.rep.dist`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md).

- n_permutations:

  Integer. Number of column-permuted null datasets used to build the
  reference distribution at each rank. Default 200.

- threshold_quantile:

  Numeric in (0, 1). A dimension is retained only if its observed
  eigenvalue exceeds this quantile of the permutation-null eigenvalues
  at the same rank. Default 0.95.

- seed:

  Integer or `NULL`. Random seed for the permutations. Default `NULL`
  leaves the global random state untouched.

- verbose:

  Logical. Print an interpretive summary? Default `TRUE`.

## Value

A list with elements:

- `k`:

  Estimated number of real dimensions (integer, at least 1).

- `eigenvalues`:

  Observed eigenvalue for every candidate dimension.

- `null_threshold`:

  The permutation-based cutoff at each rank (same length as
  `eigenvalues`).

- `n_permutations`:

  As supplied.

- `forced_to_one`:

  Logical: `TRUE` if `k` is the floored default (not even the leading
  dimension passed) rather than an actual detection – see *A known
  weakness for a single dominant dimension* above.

- `dominance_ratio`:

  Numeric, or `NA` if there was only one candidate dimension to begin
  with. The leading eigenvalue divided by the mean of the rest – a large
  value (rule of thumb: above about 3) alongside `forced_to_one = TRUE`
  suggests the floor is likely masking a real dominant dimension rather
  than reflecting an honest absence of structure (see above).

## Method

This is Horn's parallel analysis (Horn, 1965), applied to the classical
MDS decomposition of `dist_mat` rather than to raw variables directly –
a standard approach for choosing the number of meaningful ordination
axes from a distance/dissimilarity matrix (see Peres-Neto, Jackson &
Somers, 2005, for a review of this and related stopping rules).
`dist_mat` is first converted to coordinates via classical MDS
([`cmdscale`](https://rdrr.io/r/stats/cmdscale.html)), retaining every
dimension with a numerically nonzero eigenvalue as the candidate pool.
For `n_permutations` iterations, each coordinate column is independently
permuted across participants – destroying any real,
participant-identity-linked covariation between dimensions while
preserving each dimension's own marginal spread – and the resulting
matrix's covariance eigenvalues are recorded. A dimension is judged
"real" only if its observed eigenvalue exceeds `threshold_quantile` of
the permuted eigenvalues at that same rank; `k` is the largest number of
leading dimensions that all clear this bar, scanning from the top and
stopping at the first dimension that doesn't.

Unlike a numerical-rank tolerance (dropping only eigenvalues that are
zero up to floating-point roundoff – which is what
[`matrix_rank`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/matrix_rank.md)
does, and what this function's candidate pool still uses as an initial
ceiling) or a fixed total-variance-explained threshold, this adapts to
the actual noise level in the data: a dimension carrying only
per-participant noise will generally look statistically
indistinguishable from its own permuted version, however numerically
nonzero its eigenvalue is. Observed eigenvalues are recomputed from
`coords`' own covariance matrix (rather than taken directly from
`cmdscale`'s output) so the "real" side of the comparison is on the
exact same scale as the permuted side – both go through the same
[`cov()`](https://rdrr.io/r/stats/cor.html) then
[`eigen()`](https://rdrr.io/r/base/eigen.html) pipeline.

## A known weakness for a single dominant dimension

Horn's parallel analysis is well documented to be conservative at rank 1
specifically, and this can be severe enough that *even an obvious,
dominant true dimension fails to clear its own threshold* – not just a
borderline one. The reason: permutation preserves each column's own
variance exactly (only scrambling which participant has which value), so
when nearly all the real signal is concentrated in one dimension, the
permutation null's own top eigenvalue is built largely from that same
large variance, plus a small extra upward bias from incidental
correlations among the now-independent shuffled columns. In effect, the
leading dimension has to "beat a shuffled version of itself" – a bar
that stays hard to clear regardless of how strong the true signal
actually is. When this happens, `k` is floored at 1 (see `forced_to_one`
below) rather than allowed to drop to 0, but that floor is a default,
not a detection – `dominance_ratio` (also below) is provided
specifically to help tell apart "this floor is very likely masking a
real dominant dimension" from "this floor reflects a genuine absence of
detectable structure," and `verbose` output spells out which case
applies when `forced_to_one` is `TRUE`. Corroborating evidence
independent of this test (e.g. a reproducible `hclust` split, or
[`test_for_clusters`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md)'s
BIC) is the most reliable way to resolve the ambiguity.

## Examples

``` r
if (FALSE) { # \dontrun{
repdist <- get.rep.dist(icon_emb_ind)
estimate_intrinsic_dimension(repdist)
} # }
```
