# Exclude participants who fail too many catch trials

Catch trials present the target image as one of the two choices; a
correct response requires selecting the choice that matches the target.
This function removes any participant whose proportion of incorrect
catch-trial responses exceeds `max_prop_wrong`.

## Usage

``` r
filter_failed_catch(d, max_prop_wrong = 0.2)
```

## Arguments

- d:

  Data frame with columns `worker_id`, `head`, `winner`, and `loser`.

- max_prop_wrong:

  Numeric between 0 and 1. Participants with a proportion of wrong
  catch-trial responses strictly greater than this value are removed.
  Default: `0.2`.

## Value

The input data frame with rows belonging to excluded participants
removed.

## Details

A catch trial is identified by `head == winner` (correct response) or
`head == loser` (incorrect response). Only rows that satisfy one of
these conditions contribute to the catch-trial counts; other trial types
are ignored.

## Examples

``` r
if (FALSE) { # \dontrun{
d <- data.frame(
  worker_id = rep(c("p1", "p2"), each = 5),
  head      = c("cat","cat","dog","dog","cat",  "bird","bird","fish","fish","bird"),
  winner    = c("cat","dog","cat","dog","fox",   "bird","crow","fish","tuna","crow"),
  loser     = c("dog","cat","dog","cat","bear",  "crow","bird","tuna","fish","bird")
)
filter_failed_catch(d, max_prop_wrong = 0.4)
} # }
```
