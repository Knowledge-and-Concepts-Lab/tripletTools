# Test embedding model predictions.

This function generates predicted responses on a set of triplet items
given an embedding of the items, and appends the model prediction as an
additional column named ModPred to the triplet data file.

## Usage

``` r
test.model(m, vdat, isemb = TRUE)
```

## Arguments

- m:

  An embedding of the stimuli or matrix of distances among stimuli. Rows
  must have names that correspond with the triplet data.

- vdat:

  Data frame containing triplet data. Must include columns named Center,
  Left and Right, and names here must match row names of model.

- isemb:

  Is model an embedding? If T (default), compute Euclidean distance
  matrix; otherwise just treat model as the distance matrix

## Value

Returns the triplet dataframe with the column ModPred added, which
contains the predicted triplet response given the embedding/distance
matrix.

## Details

The returned object will be a data frame with an added field `ModPred`
that contains the predicted response for the triplet given the
embedding. This response will be whichever of the two choice items (Left
or Right) has the smallest Euclidean distance to the target item
(Center) in the embedding space.

If the triplet dataframe also includes a field labelled `Answer` that
contains the true, human-generated answer for the triplet, then the
model predictions can be easily converted to a proportion correct score
as follows:

`mean(output$ModPred==output$Answer)`

...where `output` is the dataframe returned by the function.

## Examples

``` r
m <- data.frame(
  x=c(1,1.1,2,2.1),
  y=c(1.25,1.75,1.25,2.75))

row.names(m) <- c("cat","dog","car","boat")

m <- as.matrix(m)

tr <- data.frame(
   Center=c("cat", "car"),
   Left = c("dog", "boat"),
   Right= c("car", "dog"))

test.model(m, tr, isemb=TRUE)
#>   Center Left Right ModPred
#> 1    cat  dog   car     dog
#> 2    car boat   dog     dog
```
