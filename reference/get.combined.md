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

head(embeddings[[1]])
#>                       dim_0       dim_1
#> CFD-BF-002-004-HO 0.3947823  0.16756907
#> CFD-BF-002-018-A  0.4886511  0.08649993
#> CFD-BF-002-022-F  0.2059984  0.10942531
#> CFD-BF-005-005-HO 0.3141250  0.12844554
#> CFD-BF-005-020-A  0.1804924 -0.31689260
#> CFD-BF-005-022-F  0.1909470 -0.32095847
```
