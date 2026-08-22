# Reduce an embedding to the lowest dimension that preserves its structure

Given an embedding fit at a generously high dimensionality and the
triplet judgments it was fit from, finds the smallest number of
dimensions that captures most of the embedding's variance (via PCA), and
reports how well the resulting lower-dimensional embedding still
predicts the triplet judgments compared to the original.

## Usage

``` r
reduce_embedding_dimension(
  embedding,
  triplet_data,
  variance_threshold = 0.95,
  max_k = NULL
)
```

## Arguments

- embedding:

  Numeric matrix (or data frame coercible to one) of embedding
  coordinates, rows = items, columns = dimensions. Row names must
  identify items.

- triplet_data:

  Data frame of one participant's triplet judgments, with columns
  `Center`, `Left`, `Right`, `Answer`, and `sampleSet` – the format
  returned by
  [`get.combined`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md)
  (one element of its output list). Every item referenced in
  `Center`/`Left`/`Right` must be a row name in `embedding`. Rows with
  `sampleAlg == "check"` (identified, per package convention, by
  `is.na(sampleSet)`) are excluded.

- variance_threshold:

  Fraction of `embedding`'s total variance (after centering) that the
  reduced embedding must retain. Default `0.95`. The reduced dimension
  `k` is the smallest number of leading principal components whose
  cumulative variance meets or exceeds this threshold – see *Details*
  for why PCA rather than classical MDS.

- max_k:

  Optional upper bound on the reduced dimension `k`, overriding
  `variance_threshold` if the threshold would otherwise select a larger
  `k`. Default `NULL` (no cap beyond `embedding`'s own numerical rank).

## Value

A named list:

- `embedding`:

  The reduced embedding: a numeric matrix with item names as row names,
  `k` columns (`dim_0`, `dim_1`, …), and mean-centered coordinates
  (embeddings are only ever compared up to rotation/translation, so
  re-adding `embedding`'s original column means back would not change
  anything downstream).

- `k`:

  The selected reduced dimension.

- `variance_explained`:

  Cumulative fraction of variance retained at `k`.

- `accuracy`:

  Fraction of `triplet_data`'s (non-check) triplets the reduced
  embedding predicts correctly – the item closer to `Center` under
  squared Euclidean distance matches `Answer`.

- `accuracy_full`:

  The same accuracy computed from the original, unreduced `embedding` –
  a reference ceiling for judging how much predictive power `k`
  dimensions preserved.

- `diagnostics`:

  Data frame with one row per candidate dimension `k = 1, ..., ` (up to
  `embedding`'s numerical rank), columns `k`, `cum_variance`, `accuracy`
  – the full curve this function's `k` was chosen from, useful for
  checking the threshold picked a sensible point (e.g. plotting
  `accuracy` or `cum_variance` against `k` to look for an elbow) rather
  than trusting a single number blindly.

## Details

The reduced embedding is the projection of `embedding`'s
(column-centered) coordinates onto their top-`k` principal components –
i.e. ordinary PCA, computed via
[`svd`](https://rdrr.io/r/base/svd.html), not classical (Torgerson)
multidimensional scaling. The two give identical results here: classical
MDS reconstructs coordinates from a distance matrix by eigendecomposing
its double-centered Gram matrix, which – when the distances are already
exact Euclidean distances of a coordinate set you have in hand, as they
are for a fitted embedding – is exactly the Gram matrix PCA operates on
directly. MDS earns its keep when you start from dissimilarities that
are *not* already known to be exact Euclidean distances from some
coordinate set (raw similarity judgments, a noisy or non-metric
dissimilarity matrix); going through that detour here would reconstruct,
at greater computational cost, the same answer PCA gets directly from
the coordinates already in hand.

`accuracy` and `accuracy_full` are both computed against *every*
non-check triplet in `triplet_data` (`sampleSet` `"train"` and `"test"`
rows alike), not just a held-out subset. This is deliberate: choosing
`k` from a single random train/test split's held-out accuracy would make
the apparent "right" dimensionality partly an artifact of which triplets
happened to land in that particular split, especially with only a few
hundred triplets per participant. Since the PCA projection itself never
looks at `triplet_data` at all (it depends only on `embedding`'s own
geometry), there is no leakage concern in scoring it against every
triplet the participant judged.

`k` is the smallest number of leading singular values whose squared sum,
divided by the squared sum of all (numerically nonzero) singular values,
meets or exceeds `variance_threshold`. Singular values below
`max(dim) * max(singular value) * .Machine$double.eps` are treated as
zero and excluded from both the numerator and denominator, matching
[`matrix_rank`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/matrix_rank.md)'s
and
[`procrustes_rank_ceiling`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/procrustes_rank_ceiling.md)'s
convention. If `variance_threshold` cannot be reached within `max_k` (or
within `embedding`'s numerical rank, if `max_k` is `NULL`), a warning
reports the achieved variance and the returned `k` is capped at
whichever limit applies.

## Examples

``` r
if (FALSE) { # \dontrun{
# emb was fit at a generous d_max (e.g. 10); triplets is that same
# participant's own judgments, as in one element of icon_triplets.
result <- reduce_embedding_dimension(emb, triplets, variance_threshold = 0.95)
result$k
result$accuracy
result$accuracy_full

# Inspect the full curve for an elbow rather than trusting one threshold
plot(result$diagnostics$k, result$diagnostics$accuracy, type = "b")
} # }
```
