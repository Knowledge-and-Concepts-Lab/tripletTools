# Exclude participants with suspiciously fast mean reaction times

Removes participants whose mean reaction time falls below a threshold,
which is used as a heuristic for detecting random or inattentive
responding. The comparison is performed on the log scale so that the
threshold is applied uniformly regardless of RT distribution skew.

## Usage

``` r
filter_fast_responders(d, min_mean_rt_ms = 1000)
```

## Arguments

- d:

  Data frame with columns `worker_id` and `rt`. `rt` will be coerced to
  numeric via [`as.numeric`](https://rdrr.io/r/base/numeric.html);
  non-numeric values become `NA` and are excluded from the mean.

- min_mean_rt_ms:

  Numeric. Minimum mean RT in milliseconds. Participants with
  `mean(rt) < min_mean_rt_ms` are removed. Default: `1000`.

## Value

The input data frame with rows belonging to excluded participants
removed.

## Examples

``` r
if (FALSE) { # \dontrun{
d <- data.frame(
  worker_id = c(rep("p1", 100), rep("p2", 100)),
  rt        = c(rnorm(100, 1500, 200), rnorm(100, 300, 50))
)
filter_fast_responders(d, min_mean_rt_ms = 1000)
# only p1 is retained
} # }
```
