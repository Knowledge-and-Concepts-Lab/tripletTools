# Get nearest k

This function takes a distance matrix and an item name and returns the
`k` nearest neighbors to the specified item.

## Usage

``` r
get.nearest.k(dmat, item, k = 5)
```

## Arguments

- dmat:

  Data matrix; rows must be named.

- item:

  String indicating the item for which nearest neighbors will be
  returned

- k:

  How many neighbors to return.

## Value

A character vector containing the `k` nearest neighbors in order of
proximity to the target item.

## Details

`dmat` must be a matrix with named rows, and `item` must match the name
of one row.

This function is useful for understanding local similarity structure in
a higher- dimensional embedding, and for creating a k-nearest-neighbor
graph of such structure.

## Examples

``` r

emb <- cfd_embeddings[[10]] #Embedding for participant 10
fdists <- as.matrix(dist(emb)) #Compute pairwise distance matrix
target <- "CFD-BF-002-004-HO"  #Name of target items

#Return 5 items nearest to target:
get.nearest.k(fdists, target, 5)
#> [1] "CFD-BM-009-003-HO" "CFD-WF-001-009-HO" "CFD-BM-002-007-HO"
#> [4] "CFD-BF-005-005-HO" "CFD-BM-038-007-HO"
```
