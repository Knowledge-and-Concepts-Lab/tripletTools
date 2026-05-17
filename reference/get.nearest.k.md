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

emb <- icon_emb_ind[[1]] #Embedding for participant 1
fdists <- as.matrix(dist(emb)) #Compute pairwise distance matrix
target <- "fdfob"  #Name of target item

#Return 5 items nearest to target:
get.nearest.k(fdists, target, 5)
#> [1] "fdfyw" "fdfow" "fdmob" "fdmyb" "fnmob"
```
