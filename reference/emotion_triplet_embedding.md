# Triplet-based embedding of 213 emotion words

A 4-dimensional embedding of 213 emotion words, fit from triplet
similarity judgments. Bundled alongside
[`emotion_bge_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/emotion_bge_embedding.md)
– a language-model embedding of the same words – as example data for
comparing triplet-based and alternative embedding spaces (see
[`procrustes_rank_ceiling`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/procrustes_rank_ceiling.md),
[`procrustes_spectral_ceiling`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/procrustes_spectral_ceiling.md)).

## Usage

``` r
emotion_triplet_embedding
```

## Format

### `emotion_triplet_embedding`

A data frame with 213 rows (one per emotion word, given as row names)
and 4 columns (`dim_0`-`dim_3`), the embedding coordinates.

## Source

Emotion words from Shaver, P., Schwartz, J., Kirson, D., & O'Connor, C.
(1987). Emotion knowledge: further exploration of a prototype approach.
*Journal of Personality and Social Psychology*, 52(6), 1061.
