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
fpath <- system.file("extdata", "cfd36_triplets_individual.csv", package = "tripletTools")

#Read the data
trips <- get.combined(fpath)

#Compute summary
part.summary <- get.participant.summary(trips)

head(part.summary)
#>   tripfile worker_id ndat         lrt      cacc  keep
#> 1    78972     78972 1012  0.77807851 1.0000000  TRUE
#> 2    78103     78103 1012  0.54139779 1.0000000  TRUE
#> 3    77827     77827 1012  0.58263855 0.9818182  TRUE
#> 4    79088     79088 1012  0.84922012 1.0000000  TRUE
#> 5    79377     79377 1012  0.27563052 0.9242424  TRUE
#> 6    80900     80900 1012 -0.09235084 0.8181818 FALSE
```
