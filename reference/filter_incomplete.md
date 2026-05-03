# Exclude participants with too few trials

Removes participants who completed fewer than `min_trials` experiment
trials, as well as any rows with a missing `worker_id`. This guards
against partially-completed sessions being included in downstream
analyses.

## Usage

``` r
filter_incomplete(d, min_trials = 510)
```

## Arguments

- d:

  Data frame with a `worker_id` column.

- min_trials:

  Integer. Minimum number of trials required for a participant to be
  retained. Default: `510`.

## Value

The input data frame with rows belonging to excluded participants (and
rows with `NA` worker IDs) removed.

## Examples

``` r
if (FALSE) { # \dontrun{
d <- data.frame(
  worker_id = c(rep("p1", 600), rep("p2", 100)),
  rt        = rnorm(700, 1500, 300)
)
filter_incomplete(d, min_trials = 510)
# only p1 is retained
} # }
```
