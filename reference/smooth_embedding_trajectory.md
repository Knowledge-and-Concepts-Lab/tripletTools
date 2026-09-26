# Smoothly averaged embedding trajectory along a 1-D latent axis

Given a list of participant embeddings and a corresponding 1-D position
for each participant along some latent axis (e.g. the leading
classical-MDS dimension of
[`get.rep.dist`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md)'s
output), computes a kernel-weighted average embedding at each of a grid
of query points along that axis – a continuous generalization of
splitting participants into discrete bins and averaging each bin's
(separately aligned) embedding. That binned approach has two rough edges
this avoids: hard bin boundaries discard real position information (two
participants who are nearly identical in position but fall either side
of a bin edge get treated as fully separate groups), and aligning each
bin's mean independently makes bin-to-bin comparisons only loosely
comparable, since each bin's own Procrustes fit is free to pick its own
rotation. Here, every participant is aligned into one shared frame once
(via
[`generalized_procrustes`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/generalized_procrustes.md)),
and every query point's average is expressed in that same frame, so the
sequence of averaged embeddings is directly comparable across the whole
trajectory.

## Usage

``` r
smooth_embedding_trajectory(
  elist,
  positions,
  query_points = NULL,
  n_query = 50,
  bandwidth = NULL,
  kernel = c("gaussian", "epanechnikov"),
  scale = TRUE,
  reflect = TRUE,
  gpa_max_iter = 100,
  gpa_tol = 1e-06
)
```

## Arguments

- elist:

  List of embeddings, one per participant, in the same format
  [`generalized_procrustes`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/generalized_procrustes.md)
  and
  [`get.rep.dist`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md)
  expect (same items, same order, same dimensionality across all
  embeddings).

- positions:

  Numeric vector, same length and order as `elist`: each participant's
  position along the latent axis, e.g.
  `cmdscale(get.rep.dist(elist), k = 1)[, 1]`.

- query_points:

  Numeric vector or `NULL`. Positions along the axis at which to
  evaluate the averaged embedding. Default `NULL` generates `n_query`
  evenly-spaced points spanning `range(positions)`.

- n_query:

  Integer. Number of query points to generate when `query_points` is
  `NULL`. Default 50.

- bandwidth:

  Numeric or `NULL`. Kernel bandwidth controlling how far along the axis
  a participant's influence extends. Default `NULL` uses
  [`bw.nrd0`](https://rdrr.io/r/stats/bandwidth.html)`(positions)`, the
  same rule-of-thumb default
  [`density`](https://rdrr.io/r/stats/density.html) uses.

- kernel:

  Character, one of `"gaussian"` (default) or `"epanechnikov"`.

- scale, reflect:

  Passed to
  [`generalized_procrustes`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/generalized_procrustes.md).

- gpa_max_iter, gpa_tol:

  Passed to
  [`generalized_procrustes`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/generalized_procrustes.md)
  as `max_iter`/`tol`.

## Value

A list with elements:

- `query_points`:

  As used (supplied or generated).

- `embeddings`:

  A list the same length as `query_points` (named by each query point's
  value), each the kernel-weighted average embedding (in the shared
  [`generalized_procrustes`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/generalized_procrustes.md)
  frame) at that point.

- `effective_n`:

  Numeric vector, same length as `query_points` – see *Interpreting
  effective_n* above.

- `bandwidth`:

  As used (supplied or estimated).

- `kernel`:

  As supplied.

- `gpa`:

  The full return value of
  [`generalized_procrustes`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/generalized_procrustes.md),
  for reference (e.g. to check `gpa$converged`, or to reuse
  `gpa$aligned` directly).

## Choosing a bandwidth

This is a smoothing-vs-resolution tradeoff, the same as for any kernel
smoother. Too wide a bandwidth washes out real local structure (a
genuine reversal or non-monotonic trend along the axis can be averaged
away entirely); too narrow leaves each query point's average dominated
by whichever one or two participants happen to sit closest to it, which
is mostly noise at realistic participant counts. The default
([`bw.nrd0`](https://rdrr.io/r/stats/bandwidth.html)) is a reasonable
starting point, not a guarantee – compare a couple of bandwidths, and
cross-check any interesting local feature (e.g. a reversal near one end)
against `effective_n` before trusting it (see below).

## Interpreting effective_n

At each query point, participants are weighted by a smooth kernel
function of their distance from that point (with the default Gaussian
kernel, no participant's weight is ever exactly zero, but distant
participants contribute negligibly). `effective_n` reports Kish's
effective sample size, \\(\sum w_i)^2 / \sum w_i^2\\, at each query
point – a standard way to express how many participants are really
driving a weighted average, on the original participant-count scale (it
equals `n` if every participant is weighted equally, and drops toward 1
as the average comes to depend on just one or two participants). Query
points near the two ends of `positions`' range are the most exposed to
this: fewer participants sit nearby, so `effective_n` is typically
lowest there, and averaged embeddings in that region should be read with
that in mind – an apparent trend near the boundary is more vulnerable to
being driven by one or two extreme participants than the same trend in
the middle of the range, where many more participants contribute.

## Examples

``` r
if (FALSE) { # \dontrun{
repdist <- get.rep.dist(icon_emb_ind)
pos <- cmdscale(repdist, k = 1)[, 1]
traj <- smooth_embedding_trajectory(icon_emb_ind, pos, n_query = 20)
traj$embeddings[[1]]
traj$effective_n
} # }
```
