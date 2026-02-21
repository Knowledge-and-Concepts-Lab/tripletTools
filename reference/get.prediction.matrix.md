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

  Type of trial to evaluate on, defaults to test trials

## Value

A matrix. Each row is an embedding, each column a triplet dataset.
Entries indicate how accurately the embedding predicts the triplet data
for the trial type indicated.

## Details

Elements of the embedding and triplet lists should be named with the
participant ID, as in the format returned by `get_combined`. Ideally
these lists will contain the same participants in the same order. The
function expects files conform to naming conventions. It first extracts
trials of the indicated type, then uses `get.hoacc` to compute the
proportion of items for which the embedding predicts the correct
response. It loops through all embeddings and datasets, returning a
matrix of the corresponding prediction accuracies.

Assuming the two lists contain the same participants in the same order,
the matrix diagonal will indicate how well a participant's own embedding
predicts their decisions on the test items (typically hold-out items not
used to compute the embedding).

## Examples

``` r
embpath <- system.file("extdata", "cfd36_embeddings_individual.csv", package = "tripletTools")
tripath <- system.file("extdata", "cfd36_triplets_individual.csv", package = "tripletTools")

#Get first five participants
embs <- get.combined(embpath, eflag=TRUE)[1:5]
trips <- get.combined(tripath, eflag = FALSE)[1:5]

pmat <- get.prediction.matrix(embs, trips, ttype="test")

pmat
#>           78972     78103     77827     79088     79377
#> 78972 0.8277512 0.5119617 0.5167464 0.5215311 0.6363636
#> 78103 0.5916230 0.7905759 0.7277487 0.7172775 0.6858639
#> 77827 0.4787234 0.7659574 0.7978723 0.7765957 0.5904255
#> 79088 0.5485437 0.8058252 0.8252427 0.8689320 0.6456311
#> 79377 0.6648045 0.6759777 0.5642458 0.5977654 0.7318436
```
