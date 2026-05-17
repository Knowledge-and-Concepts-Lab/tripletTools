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
fpath <- system.file("extdata", "cfd36_embeddings_individual.csv", package="tripletTools")

embeddings <- get.combined(fpath, eflag=TRUE)
#> Warning: file("") only supports open = "w+" and open = "w+b": using the former
#> Error in read.table(file = file, header = header, sep = sep, quote = quote,     dec = dec, fill = fill, comment.char = comment.char, ...): no lines available in input

head(embeddings[[1]])
#> Error: object 'embeddings' not found
```
