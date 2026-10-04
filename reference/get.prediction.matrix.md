# Get prediction matrix

This function takes a list of embeddings and a matched list of triplet
data and uses each embedding to predict responses on each triplet
dataset, returning the mean accuracy as a matrix.

## Usage

``` r
get.prediction.matrix(elist, tlist, ttype = "test")
```

## Arguments

- elist:

  Named list of embeddings.

- tlist:

  Named list of triplet data.

- ttype:

  Type of trial to evaluate on, defaults to test trials. Passed straight
  through to
  [`get.hoacc`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md),
  including its special `"validation"` handling.

## Value

A matrix. Each row is an embedding, each column a triplet dataset.
Entries indicate how accurately the embedding predicts the triplet data
for the trial type indicated.

## Details

Elements of the embedding and triplet lists should be named with the
participant ID, as in the format returned by `get.combined`. Ideally
these lists will contain the same participants in the same order. The
function expects files conform to naming conventions. It first extracts
trials of the indicated type, then uses `get.hoacc` to compute the
proportion of items for which the embedding predicts the correct
response. It loops through all embeddings and datasets, returning a
matrix of the corresponding prediction accuracies. The trial-type
filtering happens entirely inside
[`get.hoacc()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md)
– this function passes each participant's full triplet data frame
through unfiltered, so
[`get.hoacc()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md)'s
`sampleAlg`-based handling of `ttype = "validation"` works correctly
here too (filtering on `sampleSet` first, before
[`get.hoacc()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md)
ever saw the data, would have selected nothing for that case, since
`sampleSet` never literally equals `"validation"` once validation trials
have been excluded from training – see
[`assign_sample_sets`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/assign_sample_sets.md)).

Assuming the two lists contain the same participants in the same order,
the matrix diagonal will indicate how well a participant's own embedding
predicts their decisions on the test items (typically hold-out items not
used to compute the embedding).

## Examples

``` r
pmat <- get.prediction.matrix(icon_emb_ind, icon_triplets)
pmat
#>          3n7ggxph b5wma4no  d8mmm1qn  jn7bbjc0  pbby694o  sc2xbd6w
#> 3n7ggxph   0.6875     0.84 0.9230769 0.6521739 0.5757576 0.5714286
#> b5wma4no   0.6875     0.84 0.7692308 0.8260870 0.6363636 0.4761905
#> d8mmm1qn   0.7500     0.76 0.8461538 0.6086957 0.6363636 0.5714286
#> jn7bbjc0   0.8125     0.80 0.6923077 0.7391304 0.6666667 0.5238095
#> pbby694o   0.6875     0.68 0.6153846 0.5652174 0.8181818 0.8571429
#> sc2xbd6w   0.5625     0.68 0.5384615 0.6521739 0.7575758 0.7619048
```
