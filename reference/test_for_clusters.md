# Test whether embeddings show any cluster structure at all

Given a participant-by-participant distance matrix (e.g. from
[`get.rep.dist`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md)),
tests whether the data show any cluster structure at all – a different
question from "how many clusters," which methods like the silhouette
index only address for k \>= 2 and implicitly assume that splitting into
groups is worthwhile in the first place.

## Usage

``` r
test_for_clusters(
  dist_mat,
  max_clusters = 5,
  k_use = NULL,
  m = NULL,
  seed = NULL,
  verbose = TRUE
)
```

## Arguments

- dist_mat:

  A participant-by-participant distance matrix (or a `dist` object),
  e.g. as returned by
  [`get.rep.dist`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md).

- max_clusters:

  Integer. Maximum number of clusters to consider for the BIC comparison
  (the G = 1, "no clusters" baseline is always included in addition).
  Default 5. Must be less than the number of participants.

- k_use:

  Integer or `NULL`. Number of classical-MDS dimensions to use for both
  the Hopkins statistic and the BIC comparison. Default `NULL` estimates
  it automatically via
  [`estimate_intrinsic_dimension`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_intrinsic_dimension.md)
  – see *Dimensionality reduction* below for why this matters far more
  than it might seem. Pass an integer to bypass estimation and use a
  fixed number of dimensions directly (must be between 1 and the number
  of usable cMDS dimensions).

- m:

  Integer or `NULL`. Number of points used for the Hopkins statistic
  (see *Hopkins statistic* below). Default `NULL` uses every participant
  rather than a random subsample, since the usual motivation for
  subsampling (large datasets) rarely applies to the modest participant
  counts this function is meant for, and subsampling would just add
  unnecessary noise on top of an already small sample.

- seed:

  Integer or `NULL`. Random seed for the synthetic uniform points the
  Hopkins statistic compares against. Default `NULL` leaves the global
  random state untouched.

- verbose:

  Logical. Print an interpretive summary? Default `TRUE`.

## Value

A list with elements:

- `hopkins`:

  The Hopkins statistic (numeric, in \\\[0,1\]\\).

- `bic`:

  Named numeric vector of length `max_clusters`, the BIC (lower is
  better) for `G = 1, ..., max_clusters`.

- `hopkins_p_value`:

  Approximate one-sided p-value for `hopkins > 0.5` (see *Hopkins
  statistic* above).

- `best_g`:

  The number of clusters minimizing `bic`.

- `k_use`:

  The number of cMDS dimensions actually used – either the supplied
  `k_use` or the value estimated by
  [`estimate_intrinsic_dimension`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_intrinsic_dimension.md),
  so results stay traceable without needing to rerun the estimation
  separately.

## Dimensionality reduction

Both the Hopkins statistic and the BIC comparison need actual
coordinates, not just a distance matrix, so `dist_mat` is first
converted to coordinates via classical MDS
([`cmdscale`](https://rdrr.io/r/stats/cmdscale.html)). The number of
dimensions retained for that coordinate representation turns out to
matter a great deal – far more than it might seem, since it isn't just a
summary-for-visualization choice the way it looks at first. With
realistic individual-level noise (i.e. essentially any real
representational-distance matrix), every dimension's eigenvalue gets
pushed measurably away from zero, so a purely numerical rank check
retains nearly every available dimension (up to `n - 2`) almost
regardless of how many dimensions actually carry real signal – and the
more of those noise-only dimensions get included, the harder it becomes
for a nearest-neighbor statistic like Hopkins to detect real structure
amid them (a real 2-cluster effect that was easily detectable at a
correctly-chosen small `k` became statistically invisible once every
positive-eigenvalue dimension was retained, verified empirically during
development on real, not synthetic, data). `k_use` controls this
directly: leave it `NULL` to estimate it via
[`estimate_intrinsic_dimension`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_intrinsic_dimension.md)'s
permutation-based approach (distinguishing dimensions with real,
reproducible structure from ones that only look nonzero because of
ordinary noise), or supply it directly to bypass estimation. If a
nontrivial fraction of the total eigenvalue magnitude is negative (i.e.
`dist_mat` isn't well approximated by any Euclidean configuration), a
warning is issued; consider `cmdscale(dist_mat, add = TRUE)`'s Cailliez
correction in that case.

## Hopkins statistic

Compares nearest-neighbor distances among the real (cMDS-derived) points
to nearest-neighbor distances from synthetic points generated uniformly
at random within the same coordinate ranges, **both measured within the
same `k_use`-dimensional coordinate space** – an earlier version of this
function computed the real-to-real distances from the original,
untruncated `dist_mat` instead, which silently deflated the
synthetic-to-real distances relative to the real-to-real ones whenever
`k_use` was less than the full reconstructing dimensionality, dragging
`H` toward "less clustered than random" as an artifact of truncation
itself, regardless of whether the dropped dimensions were signal or
noise (this is what made a naive fixed small `k_use` look harmful before
the fix, when it was actually the truncation-vs-full-space mismatch that
was harmful): \\H = \sum w_i / (\sum u_i + \sum w_i)\\, where \\u_i\\
are real-to-real nearest-neighbor distances and \\w_i\\ are
synthetic-to-real nearest-neighbor distances (the simple, unweighted
ratio, as commonly implemented in software – some presentations instead
raise distances to the power of the dimensionality, which is more
faithful to the statistic's original derivation but numerically fragile
once dimensionality is more than modest). \\H\\ near 0.5 indicates no
detectable clustering; values approaching 1 indicate strong clustering
tendency. Under the null of complete spatial randomness, \\H\\ is
approximately \\Beta(m, m)\\-distributed (a commonly used approximation,
not an exact finite-sample result), giving the approximate one-sided
p-value for "H \> 0.5" returned as `hopkins_p_value`.

## BIC over number of clusters

Fits Gaussian mixture models for G = 1 (i.e. no sub-clusters) through
`max_clusters` via
[`mclustBIC`](https://mclust-org.github.io/mclust/reference/mclustBIC.html)
(requires the mclust package), taking the best (over
covariance-structure model types) BIC at each G. Reported in the
standard statistical convention (**lower is better**) – note this is the
opposite sign from what mclust reports internally, where higher is
better; values here have been negated accordingly, so "most likely
number of clusters" always means "minimizes this vector," matching
ordinary BIC-based model selection. A G with no feasible model fit (only
possible for larger G relative to a small number of participants) is
reported as `NA`.

**This BIC comparison is noticeably less reliable than the Hopkins
statistic at small-to-moderate sample sizes.** In a simulation over
purely random (no true clusters) data during development, the BIC-based
`best_g` spuriously favored more than one cluster in roughly a third of
runs at `n = 20`, versus essentially never for the Hopkins-based test at
the same n; this false-positive rate fell to roughly 5-10\\ over many
(G, covariance-structure) model combinations via BIC at small n, not a
bug – treat `best_g` as considerably less trustworthy than
`hopkins`/`hopkins_p_value` when the number of participants is small,
and prefer the Hopkins-based conclusion if the two disagree.

## Examples

``` r
if (FALSE) { # \dontrun{
repdist <- get.rep.dist(icon_emb_ind)
test_for_clusters(repdist, max_clusters = 3)
} # }
```
