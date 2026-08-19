# Triplet-based embedding of 213 animal words

A 6-dimensional embedding of 213 animal words, fit from triplet
similarity judgments. Bundled alongside
[`animal_adjacency_matrix`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/animal_adjacency_matrix.md)
– a verbal-fluency co-occurrence graph over a broader vocabulary that
includes these same 213 words – as example data for comparing
triplet-based embeddings to similarity estimated from verbal-fluency
data (see
[`successor_matrix`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/successor_matrix.md),
[`hellinger_dist`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/hellinger_dist.md),
[`procrustes_rank_ceiling`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/procrustes_rank_ceiling.md),
[`procrustes_spectral_ceiling`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/procrustes_spectral_ceiling.md)).

## Usage

``` r
animal_triplet_embedding
```

## Format

### `animal_triplet_embedding`

A data frame with 213 rows (one per animal word, given as row names) and
6 columns (`dim_0`-`dim_5`), the embedding coordinates.

## Source

Verbal-fluency data (used to select the 213-word vocabulary) from the
[Wisconsin Longitudinal Study](https://wls.wisc.edu/). Only words
produced by at least 5 participants were retained (hence "min5" in the
source file names) – see
[`animal_adjacency_matrix`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/animal_adjacency_matrix.md).
