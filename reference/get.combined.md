# Get combined data

This function reads a triplet or embedding data file containing data
from multiple participants, returning a named list with each element
containing data from one participant.

## Usage

``` r
get.combined(fname, eflag = FALSE)
```

## Arguments

- fname:

  Path to and name of the data file.

- eflag:

  Flag indicating whether data are embeddings, default FALSE

## Value

A named list, each element being a dataframe containing one
participant's data.

## Details

Data files must be in CSV format with column names in the first line.
The function assumes participant identifier labels are included in a
field called `worker_id`. If the data are embeddings, the file must
contain column names called `dim_x` where `x` is the dimension number.
Embedding data must also include a column named `item` that indicates
the item embedded at each row. The function will use this column to set
row names for each dataframe. The list elements will be labelled by the
`worker_id` value.

Use this function to read in combined (across subjects) triplet data
files (with `eflag=FALSE`) or embedding files (with `eflag=TRUE`)

## Examples

``` r
fpath <- system.file("extdata", "icon_embeddings_individual.csv", package="tripletTools")

embeddings <- get.combined(fpath, eflag=TRUE)

head(embeddings[[1]])
#>           dim_0     dim_1      dim_2
#> fdfob 0.6411938 0.9710717 -0.9336048
#> fdfow 0.5504593 0.9558654 -0.9130039
#> fdfyb 0.2907846 0.6866032 -0.6360701
#> fdfyw 0.5820549 0.9266087 -0.8992642
#> fdmob 0.5776460 1.0081034 -0.8230091
#> fdmow 0.7911357 0.4666237 -0.4759873
```
