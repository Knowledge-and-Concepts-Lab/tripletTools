# Test whether a classical-MDS dimension reflects real structure via simulation

Given a participant-by-participant distance matrix, tests whether the
proportion of variance captured by a specific classical-MDS dimension
(by default the leading one) exceeds what a dataset with no true
structure, of the same size, would typically show – by directly
simulating that null rather than relying on an asymptotic approximation
or on permutation of the observed data. Built specifically to handle the
case
[`estimate_intrinsic_dimension`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_intrinsic_dimension.md)
is documented to answer poorly: a single, clearly dominant leading
dimension (see that function's *A known weakness for a single dominant
dimension* section).

## Usage

``` r
test_dominant_dimension(
  dist_mat,
  rank = 1,
  n_simulations = 2000,
  seed = NULL,
  verbose = TRUE
)
```

## Arguments

- dist_mat:

  A participant-by-participant distance matrix (or a `dist` object),
  e.g. as returned by
  [`get.rep.dist`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md).

- rank:

  Integer. Which MDS dimension to test, by eigenvalue rank. Default 1,
  the leading dimension – the case this function was validated for (see
  *Validation* below). Other ranks are supported but have not been
  separately validated.

- n_simulations:

  Integer. Number of null datasets simulated. Default 2000.

- seed:

  Integer or `NULL`. Random seed for the simulations. Default `NULL`
  leaves the global random state untouched.

- verbose:

  Logical. Print an interpretive summary? Default `TRUE`.

## Value

A list with elements:

- `rank`:

  As supplied.

- `k_candidate`:

  Number of candidate MDS dimensions.

- `observed_proportion`:

  Proportion of total variance captured by dimension `rank` in the
  observed data.

- `null_proportion`:

  Numeric vector of `n_simulations` null values.

- `p_value`:

  Proportion of `null_proportion` at least as large as
  `observed_proportion`.

- `n_simulations`:

  As supplied.

## Method

`dist_mat` is first converted to coordinates via classical MDS
([`cmdscale`](https://rdrr.io/r/stats/cmdscale.html)), using the same
candidate-dimension pool as
[`estimate_intrinsic_dimension`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_intrinsic_dimension.md).
The test statistic is the observed proportion of total variance captured
by the requested `rank` (`eig[rank] / sum(eig[eig > 0])`) – a
scale-invariant quantity, unlike raw eigenvalue magnitude. For each of
`n_simulations` iterations, `n` points are simulated with i.i.d.
standard normal coordinates in a `k_candidate`-dimensional space (i.e.
equal variance on every candidate dimension, with no cross- dimensional
structure at all), their Euclidean distances are computed, and the same
proportion-of-variance statistic is recorded from their own classical
MDS decomposition. The p-value is the proportion of simulated values at
or above the observed one.

This is closest in spirit to Horn's original 1965 proposal for parallel
analysis (simulated random data), as opposed to the permutation variant
of Buja & Eyuboglu (1992) that
[`estimate_intrinsic_dimension`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_intrinsic_dimension.md)
implements, and is motivated by the same idea underlying the Tracy-Widom
test for the largest eigenvalue of a sample covariance matrix
(Johnstone, 2001; Patterson, Price & Reich, 2006): compare the observed
leading eigenvalue against its distribution under a null of no true
structure. The asymptotic Tracy-Widom distribution itself is not used
here — its accuracy is well documented to degrade when either the sample
size or the number of dimensions is small (exactly this package's
typical regime: participant counts in the tens, not thousands) — this
function instead simulates the exact finite-sample null directly for the
actual `n` and `k_candidate` at hand, sidestepping that approximation
entirely.

Two choices were necessary to get a test that actually works for this
package's "single dominant dimension" case, confirmed by the synthetic
validation described below rather than assumed from theory alone:
simulating the null at *equal* variance across candidate dimensions (not
matched to the observed data's own, possibly already-inflated,
per-dimension variances, the way both Horn's original method and
permutation do), and using the scale-invariant proportion-of-variance
statistic rather than raw eigenvalue magnitude. Matching the null's
variance to the observed data (as both of those alternatives do)
reintroduces exactly the self-referential problem described in
[`estimate_intrinsic_dimension`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_intrinsic_dimension.md)'s
documentation – confirmed directly: an earlier
bootstrap-eigenvector-stability design and a naive variance-matched
simulation were both tried first and both failed to distinguish genuine
synthetic structure from pure noise in testing before this design was
settled on.

## Validation

Checked directly (not assumed) across this package's realistic
participant-count range before being shipped:

- **Type I error calibration**: at n = 6, 20, and 30, the false-positive
  rate on pure-noise data was close to nominal at both alpha = 0.05
  (observed 4.7-6.7\\ 7.3-8.7\\

- **Power**: on synthetic data with a genuine dominant dimension, the
  test correctly failed to reject a weak signal (variance ratio 2) and
  correctly rejected at ratio \>= 5, at both n = 6 and n = 30.

## References

Horn, J. L. (1965). A rationale and test for the number of factors in
factor analysis. *Psychometrika*, 30(2), 179-185.

Buja, A., & Eyuboglu, N. (1992). Remarks on parallel analysis.
*Multivariate Behavioral Research*, 27(4), 509-540.

Johnstone, I. M. (2001). On the distribution of the largest eigenvalue
in principal components analysis. *Annals of Statistics*, 29(2),
295-327.

Patterson, N., Price, A. L., & Reich, D. (2006). Population structure
and eigenanalysis. *PLoS Genetics*, 2(12), e190.

## Examples

``` r
if (FALSE) { # \dontrun{
repdist <- get.rep.dist(icon_emb_ind)
test_dominant_dimension(repdist)
} # }
```
