# Get participant summary

This function takes a list of triplet data of the kind returned by
`get_combined` and from it generates a dataframe summarizing information
about each participant in the study.

## Usage

``` r
get.participant.summary(
  d,
  irange = NULL,
  mintrial = 1000,
  accthresh = 0.8,
  rtthresh = 0
)
```

## Arguments

- d:

  List of triplet data. Each element is data from one participant.

- irange:

  Vector indicating which elements of the list to include. Default is
  all.

- mintrial:

  Minimum number of trials needed to count as a complete record.

- accthresh:

  Accuracy threshould for check trials to pass quality check

- rtthresh:

  Threshold of log RT to pass quality check

## Value

Data frame containing information about each participant in the study.

## Details

The summary will include participant ID, number of completed trials,
mean accuracy on check trials, and mean log(RT) across all trials. The
arguments `accthresh` and `rtthresh` set criteria for assessing the
participant's data quality. A mean log RT of 0 or less means participant
was responding in under one second on average, usually too fast for data
to be real. Chance responding will yield an accuracy of 0.5 on check
trials, so a threshold of 0.8 means participant was likely guessing on
at least 40 percent of trials.

This function assumes standard triplet data naming conventions for
column names.

## Examples

``` r

#Path to example triplet data
fpath <- system.file("extdata", "icon_all_triplets.csv", package = "tripletTools")

#Read the data
trips <- get.combined(fpath)

#Compute summary
part.summary <- get.participant.summary(trips)

head(part.summary)
#>   tripfile worker_id ndat       lrt cacc  keep
#> 1 3n7ggxph  3n7ggxph  230 0.4961625    1 FALSE
#> 2 b5wma4no  b5wma4no  230 0.9026607    1 FALSE
#> 3 d8mmm1qn  d8mmm1qn  230 0.5051381    1 FALSE
#> 4 jn7bbjc0  jn7bbjc0  230 0.6958144    1 FALSE
#> 5 pbby694o  pbby694o  230 0.6679493    1 FALSE
#> 6 sc2xbd6w  sc2xbd6w  230 0.6507582    1 FALSE
```
