# Label each trial with its sampling algorithm

Adds a `sampleAlg` column to a trial-level data frame based on the
structure of each row. This is used with legacy data that does not
include a `trial_category` column exported directly from jsPsych. For
data collected with the current experiment template, `trial_category` is
available directly and can be renamed to `sampleAlg` instead.

## Usage

``` r
assign_sample_alg(d)
```

## Arguments

- d:

  Data frame with columns `head`, `winner`, `loser`, and `validation`.

## Value

The input data frame with an additional character column `sampleAlg`
containing `"check"`, `"validation"`, or `"random"`.

## Details

Classification rules (applied in order):

1.  If `head == winner` or `head == loser`, the trial is a catch
    (attention check) trial: `"check"`.

2.  If `validation == TRUE`, the trial is a validation trial:
    `"validation"`.

3.  Otherwise: `"random"`.

## Examples

``` r
if (FALSE) { # \dontrun{
d <- data.frame(
  head       = c("cat", "dog", "bird"),
  winner     = c("cat", "fish", "eagle"),
  loser      = c("dog", "frog", "sparrow"),
  validation = c(FALSE, FALSE, TRUE)
)
assign_sample_alg(d)
} # }
```
