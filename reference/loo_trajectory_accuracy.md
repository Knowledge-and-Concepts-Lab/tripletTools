# Leave-one-out prediction accuracy along a smoothed embedding trajectory

Evaluates, for every participant, how well the group representation at
each of a grid of points along a 1-D latent axis predicts that
participant's own held-out judgments – with each participant fully
excluded from every step of the computation that produces the
predictions tested against them (the MDS axis itself, and every smoothed
query-point embedding), not just from the held-out trials.

## Usage

``` r
loo_trajectory_accuracy(
  dist_mat,
  elist,
  triplet_list,
  n_query = 25,
  trialtype = "validation",
  bandwidth = NULL,
  kernel = c("gaussian", "epanechnikov"),
  scale = TRUE,
  reflect = TRUE,
  gpa_max_iter = 100,
  gpa_tol = 1e-06,
  verbose = TRUE
)
```

## Arguments

- dist_mat:

  A participant-by-participant distance matrix (or a `dist` object),
  e.g. as returned by
  [`get.rep.dist`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md).
  Must have the same number of participants, in the same order, as
  `elist` and `triplet_list`
  ([`get.rep.dist`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md)'s
  output does not carry participant names, so this function relies on
  matching order across all three arguments – see *Participant
  alignment* below).

- elist:

  List of embeddings, one per participant, in the same order as
  `dist_mat`'s rows/columns – the same format
  [`smooth_embedding_trajectory`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)
  and
  [`get.rep.dist`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md)
  expect (same items, same order, same dimensionality across all
  embeddings).

- triplet_list:

  List of triplet data frames, one per participant, in the same order as
  `dist_mat`/`elist` – the format
  [`get.hoacc`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md)
  expects (`Center`/`Left`/`Right`/ `Answer` columns, plus
  `sampleAlg`/`sampleSet` as needed for `trialtype`).

- n_query:

  Integer. Number of points along the manifold to evaluate for every
  participant. Default 25.

- trialtype:

  Passed to
  [`get.hoacc`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md)
  – which trials count as this participant's held-out set. Default
  `"validation"` (identified via `sampleAlg`, matching
  [`get.hoacc`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md)'s
  own special-casing of that value – see its documentation).

- bandwidth, kernel, scale, reflect, gpa_max_iter, gpa_tol:

  Passed to each leave-one-out call of
  [`smooth_embedding_trajectory`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md).

- verbose:

  Logical. Print progress (one line per participant, since this refits
  the full trajectory once per participant)? Default `TRUE`.

## Value

A list with elements:

- `accuracy`:

  `n` x `n_query` matrix (rows = participants, in `dist_mat`'s order;
  columns = query-point rank 1..`n_query`). Each entry is that
  participant's held-out prediction accuracy from the leave-one-out
  trajectory's embedding at that query-point rank.

- `query_points`:

  `n` x `n_query` matrix of the actual manifold positions used for each
  participant's own leave-one-out trajectory – these differ slightly
  participant to participant, since each is computed from a different
  (n-1)-participant range (see
  [`smooth_embedding_trajectory`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)'s
  own `query_points` behavior).

- `effective_n`:

  `n` x `n_query` matrix of Kish's effective sample size at each query
  point of each participant's leave-one-out trajectory – see
  [`smooth_embedding_trajectory`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)'s
  *Interpreting effective_n* section.

- `full_sample_position`:

  Numeric vector, length `n`: each participant's own position from the
  *full* (not leave-one-out) sample's `cmdscale(dist_mat, k = 1)` – for
  reference/context only (e.g. to relate accuracy along the manifold
  back to roughly where this participant themselves sits), never used in
  computing any prediction.

## Why this exists – a real data-leakage pitfall

Calling
[`smooth_embedding_trajectory`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)
once on the full participant list, and then evaluating each
participant's held-out trials against the query point nearest their own
position, looks like a clean train/test split – held-out trials were
never used to fit anything – but it is not: every query point's smoothed
embedding is a weighted average that includes every participant, with
*no participant's weight ever exactly zero* (see that function's own
documentation), so the embedding being evaluated against a participant
partially consists of that participant's own (already-fitted) embedding.
Confirmed directly (not just argued): a synthetic dataset of
participants with fully independent, unrelated true embeddings – zero
true shared structure, by construction – produced a strong,
"significant"-looking crossover pattern (left-end embedding predicts
left-end participants, right-end predicts right-end) when evaluated this
way (R-squared 0.27, p = 0.003), which collapsed to non-significance
(R-squared 0.06, p = 0.18) once each participant was properly excluded
from the computation. This function does the full version of that
exclusion: `dist_mat` is subset to drop the held-out participant
*before* [`cmdscale`](https://rdrr.io/r/stats/cmdscale.html) computes
the 1-D axis (not just before the smoothing step), so the axis itself –
not only the averaged embeddings along it – is entirely out-of-sample
for the participant being evaluated.

## Participant alignment

[`get.rep.dist`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md)
does not currently propagate participant names into its output matrix's
dimnames, so this function matches `dist_mat`, `elist`, and
`triplet_list` *by position*, not by name – a mismatched order across
the three arguments will silently evaluate the wrong participant's
trials against the wrong leave-one-out trajectory. If `elist` and
`triplet_list` both have names, they are checked for identical order as
a safety check; `dist_mat` itself is not checked, since it typically has
none.

## Examples

``` r
if (FALSE) { # \dontrun{
repdist <- get.rep.dist(icon_emb_ind)
res <- loo_trajectory_accuracy(repdist, icon_emb_ind, icon_triplets, n_query = 10)
res$accuracy
} # }
```
