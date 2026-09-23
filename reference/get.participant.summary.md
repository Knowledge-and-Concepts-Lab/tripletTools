# Get participant summary

This function takes a list of triplet data of the kind returned by
`get.combined` and from it generates a dataframe summarizing information
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

Data frame containing information about each participant in the study,
with one row per participant and columns:

- `tripfile`:

  Name of the list element (usually a file/participant identifier), from
  `names(d)`.

- `worker_id`:

  Participant identifier, from the `worker_id` column.

- `ndat`:

  Number of trials (rows) for this participant.

- `lrt`:

  Mean log response time, in seconds, across all trials.

- `cacc`:

  Proportion correct on check trials (`sampleAlg == "check"`); `1.0` if
  the participant has no (or only one) check trial, since accuracy can't
  meaningfully be assessed from that little data – this is an automatic
  pass, not evidence of good performance.

- `ncheck`, `nvalidation`:

  Number of trials with `sampleAlg` equal to `"check"` / `"validation"`
  respectively. `0` (not an error) if `sampleAlg` isn't a column in this
  participant's data at all – some studies never use check/validation
  trials.

- `ntrain`, `ntest`:

  Number of trials with `sampleSet` equal to `"train"` / `"test"`
  respectively. Also `0`, not an error, if `sampleSet` is missing.

- `keep`:

  Logical flag: `FALSE` if this participant fails any of the
  `accthresh`/`rtthresh`/`mintrial` criteria below.

- Any other constant-per-participant column:

  See *Extra participant-level fields* below – present only if at least
  one participant's data actually has such a column, so this may add
  zero or several columns depending on `d`.

## Details

The summary always includes participant ID, number of completed trials,
mean accuracy on check trials, mean log(RT) across all trials, and a
breakdown of trial counts by `sampleAlg`/`sampleSet` (see *Return*). The
arguments `accthresh` and `rtthresh` set criteria for assessing the
participant's data quality. A mean log RT of 0 or less means participant
was responding in under one second on average, usually too fast for data
to be real. Chance responding will yield an accuracy of 0.5 on check
trials, so a threshold of 0.8 means participant was likely guessing on
at least 40 percent of trials.

This function assumes standard triplet data naming conventions for
column names.

## Extra participant-level fields

Real triplet data files sometimes carry additional columns beyond the
standard ones – e.g. which of several task variants a participant
performed, or other per-session metadata recorded alongside every trial.
Any column (other than `worker_id`, which is already the dedicated
identifier column above) that takes exactly one distinct non-`NA` value
across a given participant's rows is assumed to be participant-level
metadata rather than per-trial data, and is carried through to the
summary automatically under its own original column name – no need to
list such columns in advance, since which ones qualify depends entirely
on `d`. A column that varies within a participant's own rows (as
`Center`, `rt`, etc. always will) is correctly left out for that
participant, with no special-casing needed to exclude the standard
trial-level columns by name. If a qualifying column is constant for at
least one participant but not for another (or missing from another's
data entirely), that participant gets `NA` in the corresponding column
rather than the whole column being dropped. These extra columns are
always returned as character, regardless of the original column's type,
since a single output column may need to hold values collected from
participants whose data had that column stored as different types.

## Examples

``` r

#Path to example triplet data
fpath <- system.file("extdata", "icon_all_triplets.csv", package = "tripletTools")

#Read the data
trips <- get.combined(fpath)

#Compute summary
part.summary <- get.participant.summary(trips)

head(part.summary)
#>   tripfile worker_id ndat       lrt cacc ncheck nvalidation ntrain ntest  keep
#> 1 3n7ggxph  3n7ggxph  230 0.4961625    1     10          20    204    16 FALSE
#> 2 b5wma4no  b5wma4no  230 0.9026607    1     10          20    195    25 FALSE
#> 3 d8mmm1qn  d8mmm1qn  230 0.5051381    1     10          20    207    13 FALSE
#> 4 jn7bbjc0  jn7bbjc0  230 0.6958144    1     10          20    197    23 FALSE
#> 5 pbby694o  pbby694o  230 0.6679493    1     10          20    187    33 FALSE
#> 6 sc2xbd6w  sc2xbd6w  230 0.6507582    1     10          20    199    21 FALSE
```
