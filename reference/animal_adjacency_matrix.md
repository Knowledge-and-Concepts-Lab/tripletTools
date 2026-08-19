# Verbal-fluency co-occurrence graph for 295 animal words

A directed, weighted adjacency matrix built from verbal-fluency data:
participants listed as many animals as they could think of, and an edge
from word A to word B is weighted by the number of times B immediately
followed A across all lists. Bundled alongside
[`animal_triplet_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/animal_triplet_embedding.md)
as example data for estimating similarity from verbal-fluency data via
[`successor_matrix`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/successor_matrix.md)
and
[`hellinger_dist`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/hellinger_dist.md),
and comparing the resulting distances to a triplet-based embedding of
the same items.

## Usage

``` r
animal_adjacency_matrix
```

## Format

### `animal_adjacency_matrix`

A 295 x 295 numeric matrix with row and column names giving the animal
word at each position. Entry `[i, j]` is the number of times word `j`
immediately followed word `i` across all participants' lists.

## Source

Verbal-fluency data from the [Wisconsin Longitudinal
Study](https://wls.wisc.edu/).

## Details

Only words produced by at least 5 participants are included (hence
"min5" in the source file names). This vocabulary is broader than
[`animal_triplet_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/animal_triplet_embedding.md)'s
213 items – it includes 82 additional words (superordinate terms like
"animal", synonyms/variants, and other species) that appeared in fluency
lists but weren't part of the curated triplet stimulus set. All 213
triplet-embedded items are present among these 295.

When comparing successor-representation-based distances to
[`animal_triplet_embedding`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/animal_triplet_embedding.md),
compute
[`successor_matrix`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/successor_matrix.md)
on the full 295-word graph first, and only restrict to the 213 matching
items afterward (subsetting rows and columns of the resulting successor
matrix) – this preserves genuine multi-hop associative structure that
passes through a non-target word (e.g. bear -\> cub -\> lion), which
would be lost if the adjacency matrix were restricted to the 213 items
before computing the successor representation.
