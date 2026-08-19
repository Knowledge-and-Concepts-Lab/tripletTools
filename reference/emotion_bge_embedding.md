# Language-model embedding of 213 emotion words (BAAI/bge-m3)

An embedding of the same 213 emotion words as
[`emotion_triplet_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/emotion_triplet_embedding.md),
generated from the word strings by the
[BAAI/bge-m3](https://huggingface.co/BAAI/bge-m3) language model.
Bundled as example data for comparing a low-dimensional triplet-based
embedding against a much higher-dimensional alternative (see
[`procrustes_rank_ceiling`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/procrustes_rank_ceiling.md),
[`procrustes_spectral_ceiling`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/procrustes_spectral_ceiling.md)).

## Usage

``` r
emotion_bge_embedding
```

## Format

### `emotion_bge_embedding`

A data frame with 213 rows (one per emotion word, given as row names)
and 212 columns (`pc_001`-`pc_212`), the embedding coordinates.

## Source

Emotion words from Shaver, P., Schwartz, J., Kirson, D., & O'Connor, C.
(1987). Emotion knowledge: further exploration of a prototype approach.
*Journal of Personality and Social Psychology*, 52(6), 1061. Embeddings
generated from the word strings with the
[BAAI/bge-m3](https://huggingface.co/BAAI/bge-m3) model.

## Details

bge-m3 natively outputs a 1024-dimensional embedding per word. With only
213 items, however, the centered coordinate matrix cannot have rank
above 212 (`n - 1`) regardless of that native width – confirmed directly
with
[`matrix_rank`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/matrix_rank.md)
on the raw 1024-dimensional embedding. This dataset stores that
embedding rotated onto its own top 212 principal components rather than
the full 1024 raw dimensions. Because every Procrustes-based comparison
in this package is invariant to orthogonal rotation of either input,
this rotation loses nothing for that purpose – confirmed with
`procrustes_spectral_ceiling(emotion_bge_embedding, <original 1024-dim embedding>)`,
which equals 1 to six decimal places – while cutting the on-disk size by
roughly 80%. See `data-raw/emotion_embeddings.R` for the full derivation
and verification.
