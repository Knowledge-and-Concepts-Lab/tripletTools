# Test how stable a hierarchical-clustering partition is under resampling

Given a participant-by-participant distance matrix and a chosen number
of clusters `k` (e.g. from
[`test_for_clusters`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md)'s
`best_g`, or any `k` you're using with
[`cutree`](https://rdrr.io/r/stats/cutree.html)), repeatedly refits the
same
[`hclust`](https://rdrr.io/r/stats/hclust.html)/[`cutree`](https://rdrr.io/r/stats/cutree.html)
pipeline on random subsamples of participants and compares each
resampled partition back to the full-data partition. A partition that
reflects real structure should reappear reliably across resamples; a
partition that happens to look clean in one fit but doesn't survive
resampling is more likely to be fitting this particular sample's noise,
however interpretable the story attached to it feels.

## Usage

``` r
test_cluster_stability(
  dist_mat,
  k,
  method = "ward.D",
  n_reps = 500,
  subsample_frac = 0.8,
  seed = NULL,
  verbose = TRUE
)
```

## Arguments

- dist_mat:

  A participant-by-participant distance matrix (or a `dist` object),
  e.g. as returned by
  [`get.rep.dist`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md).

- k:

  Integer. The number of clusters to cut the tree into (must be at least
  2 and leave enough participants per resample – see `subsample_frac`).

- method:

  Linkage method passed to
  [`hclust`](https://rdrr.io/r/stats/hclust.html). Default `"ward.D"`,
  matching the convention used elsewhere in this package (e.g.
  [`pacc.by.cluster`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/pacc.by.cluster.md)'s
  example,
  [`get.group.list.mean`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.group.list.mean.md)'s
  example).

- n_reps:

  Integer. Number of resamples. Default 500.

- subsample_frac:

  Numeric in (0, 1). Fraction of participants kept in each resample
  (drawn without replacement). Default 0.8. Must leave more than `k`
  participants per resample.

- seed:

  Integer or `NULL`. Random seed for the resampling. Default `NULL`
  leaves the global random state untouched.

- verbose:

  Logical. Print an interpretive summary? Default `TRUE`.

## Value

A list with elements:

- `ari`:

  Numeric vector of length `n_reps`: the Adjusted Rand Index between
  each resampled partition and the full-data partition (see *Adjusted
  Rand Index* above).

- `mean_ari`, `median_ari`:

  Mean and median of `ari`.

- `participant_stability`:

  Named numeric vector (one entry per participant, named from
  `dist_mat`'s labels if present): for each participant, the fraction of
  same-resample pairwise co-clustering decisions (same cluster vs.
  different cluster, against every other participant who happened to be
  resampled alongside them) that agreed with the full-data partition,
  averaged over every resample that included them. Lower values flag
  participants whose cluster assignment is the least reproducible – not
  necessarily wrong, but the most sensitive to exactly which other
  participants happen to be in the sample.

- `orig_labels`:

  Named integer vector: the full-data
  `cutree(hclust(dist_mat, method), k)` partition being tested, for
  reference.

- `k`, `n_reps`, `subsample_frac`, `method`:

  The arguments used, echoed back for traceability.

## Why resampling rather than another internal quality metric

The Hopkins statistic, BIC, and silhouette index (see
[`test_for_clusters`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md))
all evaluate a clustering against some assumption about cluster shape
(spherical, elliptical-Gaussian, etc.), so disagreement between them
often just reflects that the true structure doesn't cleanly match any
one of those idealized shapes – it doesn't resolve which, if any,
clustering is trustworthy. A partition that "makes sense" on inspection
is also weak evidence on its own: with a modest number of participants,
a plausible-sounding story can usually be told about almost any split
after the fact. Resampling stability instead asks a question that
doesn't depend on cluster shape or a subjective read of the result: if
the data collection were repeated (approximated here by holding out a
random subset of participants each time), would the same grouping of
people reappear? This is a necessary condition for a partition to
reflect real, sample-independent structure, though (like any single
diagnostic here) not by itself sufficient – the strongest validation
remains an external variable, not used to build the clustering, that the
partition predicts.

## Adjusted Rand Index

Each resample's partition is compared to the full-data partition
(restricted to the resampled participants) via
[`adjustedRandIndex`](https://mclust-org.github.io/mclust/reference/adjustedRandIndex.html),
which is 1 for identical partitions, approximately 0 for agreement no
better than a random relabeling, and can go negative for agreement
systematically worse than chance. `mean_ari`/`median_ari` summarize this
across all `n_reps` resamples.

## What "stable" does and doesn't mean

This function tests whether *this specific sample's* partition keeps
reappearing when a subset of it is resampled – it does not test whether
the underlying population actually has cluster structure (that is what
[`test_for_clusters`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md)'s
Hopkins statistic is for). A clumpy-looking split that arose purely by
chance in one finite sample can still resample as highly stable, because
subsampling mostly repeats the same fixed points rather than redrawing
new ones. Concretely: in checks on purely random, structure-free data
during development, mean ARI averaged around 0.67 at n = 20 and around
0.38 at n = 60 (individual draws ranging from about 0.2 to 0.85) –
noticeably far from the 0 you might expect for "no real clusters," and
worse at smaller n, echoing the small-n false-positive pattern already
documented for
[`test_for_clusters`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md)'s
BIC comparison. Treat a high `mean_ari` as evidence a partition survives
resampling, not as evidence it reflects genuine population structure on
its own – interpret it together with a significant Hopkins result, and
treat an external, independently-measured correlate of cluster
membership as the strongest available validation.

## Examples

``` r
if (FALSE) { # \dontrun{
repdist <- get.rep.dist(icon_emb_ind)
clusters <- test_for_clusters(repdist, max_clusters = 3)
test_cluster_stability(repdist, k = clusters$best_g)
} # }
```
