# Get hold-out prediction accuracy

This function computes embedding prediction accuracy on held-out items.

## Usage

``` r
get.hoacc(em, td, trialtype = "test", isemb = TRUE)
```

## Arguments

- em:

  Embedding or distance matrix for generating predictions.

- td:

  Dataframe containing triplet data to be evaluated.

- trialtype:

  Type of trial to be evaluated, defaults to `test`

- isemb:

  When true, `em` is a matrix of embedding coordinates; when false, it
  is assumed to be a distance matrix.

## Value

A real-valued number indicating the proportion of trials (of the
indicated type) for which the prediction was correct.

## Details

This is a wrapper function for `test.model` that computes the predicted
response for each triplet of the specified type in the triplet dataset,
then compares this to the true answer and computes the proportion of
trials for which the prediction is matched.

Triplet data must be in dataframe objects containing columns labeled
`Center`, `Left`, `Right`, and `Answer` as well as a column labeled
`sampleSet` that indicates the trial type for each triplet. Embedding
data must be a numeric matrix (or coercible to one) containing either
the embedding coordinates for each item or a matrix of item-to-item
distances.

## Examples

``` r
m <- data.frame(
  x=c(1,1.1,2,2.1),
  y=c(1.25,1.75,1.25,1.75))

row.names(m) <- c("cat","dog","car","boat")

m <- as.matrix(m)

tr <- data.frame(
   Center=c("cat", "car", "dog", "boat"),
   Left = c("dog", "boat", "car", "cat"),
   Right= c("car", "dog", "boat", "car"),
   Answer=c("dog", "boat", "car", "car"),
   sampleSet=c("test","test","test", "test"))

get.hoacc(m, tr, isemb=TRUE)
#> [1] 0.75
```
