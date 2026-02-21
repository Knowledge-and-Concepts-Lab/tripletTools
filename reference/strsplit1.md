# Split a string

Split a string

## Usage

``` r
strsplit1(x, split)
```

## Arguments

- x:

  A character vector with one element.

- split:

  What to split on.

## Value

A character vector.

## Examples

``` r
x <- "alfa,bravo,charlie,delta"
strsplit1(x, split = ",")
#> [1] "alfa"    "bravo"   "charlie" "delta"  
```
