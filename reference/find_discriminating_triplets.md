# Find triplets where two embeddings make discrepant predictions

Given two embeddings of the same items, finds triplets (a head item and
two options) for which the embeddings imply very different answers about
which option is closer to the head – useful for designing a follow-up
study to test which embedding better matches human similarity judgments.

## Usage

``` r
find_discriminating_triplets(
  embedding1,
  embedding2,
  k = 10L,
  mu = 0.05,
  n_candidates = 200000L,
  max_per_item = Inf,
  seed = NULL
)
```

## Arguments

- embedding1, embedding2:

  Numeric matrices (or data frames coercible to one) of embedding
  coordinates, rows = items, columns = dimensions. Row names must
  identify items, and both embeddings must contain the same set of items
  (order may differ; dimensionality may differ between the two
  embeddings).

- k:

  Number of triplets to return. Default `10L`.

- mu:

  CKL model constant, matching the crowd kernel noise model this
  package's embedding pipeline is fit under (see *Details*). Default
  `0.05`.

- n_candidates:

  Number of candidate triplets to sample and score before selecting the
  top `k`. Default `200000L`. Half are drawn uniformly at random; half
  are drawn with items weighted by how much their
  distance-to-other-items profile differs between the two embeddings
  (see *Details*), concentrating search on items likely to matter
  without excluding any item outright. For small item sets, a large
  enough value effectively covers every distinct triplet (duplicates are
  removed automatically), approximating exhaustive search without a
  separate code path for it.

- max_per_item:

  Maximum number of returned triplets any single item may appear in (as
  head or either option). Default `Inf` (no cap). Useful when a handful
  of items are placed very differently between the two embeddings and
  would otherwise dominate the results.

- seed:

  Optional integer random seed for reproducible candidate sampling.
  Default `NULL` (no seed set).

## Value

A data frame with one row per selected triplet, sorted by decreasing
discrepancy, with columns:

- `head`, `option1`, `option2`:

  Item names.

- `embedding1_predicts`, `embedding2_predicts`:

  Which option (`option1` or `option2`) each embedding predicts is
  closer to the head.

- `p_embedding1`, `p_embedding2`:

  Each embedding's CKL probability that `option1` is the closer option.

- `discrepancy`:

  The symmetric KL divergence between the two embeddings' predicted
  probabilities for this triplet – see *Details*.

If fewer than `k` triplets with positive discrepancy can be selected
from the sampled candidates – because `max_per_item` is restrictive, or
because the two embeddings simply agree on everything else sampled – a
warning reports how many were found and the returned data frame has
fewer than `k` rows.

## Details

For a triplet with head `h` and options `A`/`B`, each embedding's CKL
probability that `A` is closer than `B` is
`p = (mu + d(h,B)) / (2*mu + d(h,A) + d(h,B))`, where `d` is squared
Euclidean distance within that embedding's own coordinates – the same
probability model (including the `mu` constant) used by this package's
embedding-fitting backend. Calling `p1`/`p2` the two embeddings'
probabilities for a triplet, `discrepancy` is the symmetric KL
divergence between `Bernoulli(p1)` and `Bernoulli(p2)`. This is zero
exactly when the embeddings agree (`p1 == p2`), including when both are
highly uncertain (`p1 == p2 == 0.5`) – a plain sum of cross-entropies
would instead score such genuinely-ambiguous-but-agreeing triplets as
artificially "discrepant," since cross-entropy has an entropy floor even
between identical distributions.

Because the number of possible triplets grows as `n*(n-1)*(n-2)/2`,
exhaustive search is not attempted; candidates are sampled instead (see
`n_candidates`). Half of every candidate pool is drawn uniformly at
random; the other half is drawn with items weighted by `1 - ` their
distance-profile Spearman correlation (the same measure used by
[`find_discrepant_items`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_discrepant_items.md)):
for each item, its vector of distances to every other item is compared
between `embedding1` and `embedding2`, and items whose relative position
differs more between the two embeddings get a larger weight and are
sampled more often. This is a soft bias on candidate *generation* only:
every item retains nonzero sampling probability (a small floor is added
to the weights), and the final ranking always comes from the exact
`discrepancy` score above, so a misleading weight can cost search
efficiency but never correctness. An earlier version of this function
weighted items by their residual from a Procrustes alignment of
`embedding1` onto `embedding2` instead; that was replaced because a
single strong outlier item can distort the *global* rotation/ scale a
Procrustes fit uses to minimize total residual, inflating the apparent
residual of other, unchanged items enough that they outrank the true
outlier (verified: on a 20-item synthetic example with exactly one item
relocated, the Procrustes residual ranked that item only 3rd, with a
weight barely distinguishable from the top-ranked item, while the
Spearman-based weight used here ranks it 1st with more than 3x the
next-highest item's weight). The distance-profile approach has no shared
fitting step, so it does not share this failure mode; the 50/50 uniform
component is retained regardless, as a general hedge against any
remaining imperfection in the weighting heuristic.

Selection among scored candidates is a greedy pass in decreasing order
of `discrepancy`, skipping any candidate that would push one of its
three items over `max_per_item`, and skipping candidates with
`discrepancy <= 0` outright – such a candidate means the two embeddings
agree on that triplet, which is never useful for the stated purpose
regardless of how many triplets have already been selected. This
selection is an approximation, not a globally optimal selection under
the `max_per_item` constraint, but one consistent with only needing
"good enough" triplets rather than a provably best set.

## Examples

``` r
set.seed(1)
n <- 20
embedding1 <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))
embedding2 <- embedding1
embedding2["item1", ] <- embedding2["item1", ] + 10   # one item moved far away

find_discriminating_triplets(embedding1, embedding2, k = 5)
#>     head option1 option2 embedding1_predicts embedding2_predicts p_embedding1
#> 1 item13   item4   item1               item1               item4   0.05227651
#> 2 item13   item1  item15               item1              item15   0.92644295
#> 3 item13   item1  item11               item1              item11   0.90414082
#> 4 item13   item1   item8               item1               item8   0.90396788
#> 5 item13  item14   item1               item1              item14   0.10624393
#>   p_embedding2 discrepancy
#> 1   0.96579676    5.698675
#> 2   0.02401291    5.629493
#> 3   0.01809171    5.527306
#> 4   0.01805633    5.526448
#> 5   0.98383251    5.474528

# Cap how often any single item (e.g. the one moved above) can appear
find_discriminating_triplets(embedding1, embedding2, k = 5, max_per_item = 2)
#> Warning: Only found 2 of the requested 5 triplets (either exhausted candidates with positive discrepancy, or max_per_item = 2 was too restrictive) among 3420 sampled candidates. Increase n_candidates or relax max_per_item.
#>     head option1 option2 embedding1_predicts embedding2_predicts p_embedding1
#> 1 item13   item1   item4               item1               item4   0.94772349
#> 2 item13  item15   item1               item1              item15   0.07355705
#>   p_embedding2 discrepancy
#> 1   0.03420324    5.698675
#> 2   0.97598709    5.629493
```
