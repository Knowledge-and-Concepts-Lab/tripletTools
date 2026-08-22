# Find items whose relative position differs most between two embeddings

Given two embeddings of the same items, ranks items by how much their
distance profile to every other item differs between the two spaces – a
way to find which specific items are placed most differently, without
needing to align the two embeddings first (unlike Procrustes-based
comparisons).

## Usage

``` r
find_discrepant_items(
  embedding1,
  embedding2,
  k = NULL,
  method = c("spearman", "pearson")
)
```

## Arguments

- embedding1, embedding2:

  Numeric matrices (or data frames coercible to one) of embedding
  coordinates, rows = items, columns = dimensions. Row names must
  identify items, and both embeddings must contain the same set of items
  (order may differ). Dimensionality may differ between the two
  embeddings – this function never needs to align them, since it only
  ever compares distances computed within each embedding's own space.

- k:

  Number of most-discrepant items to return. Default `NULL` returns
  every item, ranked.

- method:

  Correlation method, passed to
  [`cor`](https://rdrr.io/r/stats/cor.html). Default `"spearman"` – see
  *Details* for why this is deliberately not `"pearson"`.

## Value

A data frame with one row per item (or per the top `k`, if set), sorted
by ascending correlation (most discrepant first), with columns `item`
and `correlation`.

## Details

For each item, this compares its vector of distances to every other item
in `embedding1` against the same vector in `embedding2`, via
[`cor`](https://rdrr.io/r/stats/cor.html). A low correlation means that
item's position *relative to everything else* differs between the two
embeddings – regardless of any overall rotation, reflection, or
rescaling difference between the two spaces, since Euclidean distance is
already invariant to all of those. Unlike a Procrustes-based comparison,
there is no dimensionality padding/alignment step to worry about:
distances are computed within each embedding's own space, so the two
embeddings can have entirely different dimensionality.

**Use `method = "spearman"`, not `"pearson"`.** A single badly-placed
item corrupts one distance entry for every *other* item's profile too
(their distance to that one item) while leaving the rest of each such
profile untouched. Pearson correlation is highly sensitive to a single
extreme value and can be dragged down by that one corrupted entry even
when the other entries are perfectly preserved – verified directly: in a
synthetic test with exactly one relocated item, Pearson correlation
ranked that item outside the overall bottom 5 entirely, while Spearman
correlation (which compresses a single extreme value's effect via
ranking rather than raw magnitude) ranked it a clear, decisive first,
with every other item's correlation far higher.

This complements
[`find_discriminating_triplets`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_discriminating_triplets.md)
(which finds *triplets* two embeddings disagree on) and is a more robust
alternative to inspecting per-item Procrustes residuals for finding
discrepant *items* directly. A Procrustes fit (as used by
[`procrustes_rank_ceiling`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/procrustes_rank_ceiling.md)/[`procrustes_spectral_ceiling`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/procrustes_spectral_ceiling.md))
shares a single rotation/scale across every item, so one badly-placed
item can distort that shared fit enough to inflate *other*, unrelated
items' apparent residuals above the true outlier's own (verified in this
same synthetic test: Procrustes residuals ranked a different, unrelated
item first). This function has no shared fitting step – each item's
score depends only on its own distances in each space, independent of
every other item's placement (aside from the much smaller contamination
described above, which `method = "spearman"` already resists).

With very few items, per-item correlations are computed over few points
and become noisy – treat rankings cautiously for small item sets.

## Examples

``` r
set.seed(1)
n <- 20
embedding1 <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))
embedding2 <- embedding1
embedding2["item1", ] <- embedding2["item1", ] + 10   # one item moved far away

find_discrepant_items(embedding1, embedding2, k = 5)
#>     item correlation
#> 1  item1  0.05087719
#> 2  item6  0.73157895
#> 3 item14  0.73157895
#> 4  item2  0.76140351
#> 5  item3  0.76140351
```
