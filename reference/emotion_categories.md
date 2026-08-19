# Basic emotion categories for the 213 Shaver emotion words

Shaver et al. (1987) basic-emotion category assignments for the same 213
emotion words as
[`emotion_triplet_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/emotion_triplet_embedding.md)
and
[`emotion_bge_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/emotion_bge_embedding.md).
Bundled as an example categorical label for evaluating an embedding via
classifier performance (see
[`repeated_stratified_multinomial_cv`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/repeated_stratified_multinomial_cv.md)).

## Usage

``` r
emotion_categories
```

## Format

### `emotion_categories`

A data frame with 213 rows (one per emotion word, given as row names,
matching
[`emotion_triplet_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/emotion_triplet_embedding.md)/
[`emotion_bge_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/emotion_bge_embedding.md))
and one column:

- `category`:

  Factor with 7 levels: `"Love"`, `"Joy"`, `"Surprise"`, `"Anger"`,
  `"Sadness"`, `"Fear"`, and `"Absent"`.

## Source

Shaver, P., Schwartz, J., Kirson, D., & O'Connor, C. (1987). Emotion
knowledge: further exploration of a prototype approach. *Journal of
Personality and Social Psychology*, 52(6), 1061.

## Details

`"Absent"` (78 words) marks words Shaver et al. did not end up assigning
to a basic-emotion category – these are typically excluded before
classification. `"Surprise"` has only 3 words, too few for reliable
cross-validated classification (with `folds <= 3` and a single held-out
item per fold, there's no stable way to estimate that class's
performance) – it's usually worth excluding too, leaving 132 words
across 5 categories (Anger 29, Fear 17, Joy 33, Love 16, Sadness 37).
Both are kept in this dataset rather than pre-filtered out, so that
filtering step can be shown explicitly rather than hidden in
`data-raw/emotion_categories.R`.
