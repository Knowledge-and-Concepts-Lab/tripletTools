# Test embedding model predictions.

This function generates predicted responses on a set of triplet items
given an embedding of the items, and appends the model prediction as an
additional column to the triplet data file, named after the embedding
argument itself by default (see `pred_name` below).

## Usage

``` r
test.model(m, vdat, isemb = TRUE, pred_name = NULL)
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

- pred_name:

  Character or `NULL` (default). Name of the appended prediction column.
  When `NULL`, this is derived automatically from the expression passed
  as `m` – e.g. `test.model(icon3d, valsum)` names the column `icon3d` –
  sanitized with [`make.names`](https://rdrr.io/r/base/make.names.html)
  so it's always a valid column name (this matters most when `m` is
  passed as something other than a plain variable name, e.g.
  `test.model(embeddings[[1]], valsum)`, where the derived name will be
  the sanitized deparsed expression rather than something meaningful).
  Set this explicitly for a predictable name regardless of how `m` is
  passed, e.g. when calling `test.model` from inside another function.

## Value

Returns the triplet dataframe with the prediction column added, which
contains the predicted triplet response given the embedding/distance
matrix.

## Details

The returned object will be a data frame with an added field (named per
`pred_name` above) that contains the predicted response for the triplet
given the embedding. This response will be whichever of the two choice
items (Left or Right) has the smallest Euclidean distance to the target
item (Center) in the embedding space.

If the triplet dataframe also includes a field labelled `Answer` that
contains the true, human-generated answer for the triplet, then the
model predictions can be easily converted to a proportion correct score
as follows:

`mean(output$ModPred==output$Answer)`

...where `output` is the dataframe returned by the function, and
`ModPred` is replaced by whatever `pred_name` was used (see above).

## Examples

``` r
toy_embedding <- data.frame(
  x=c(1,1.1,2,2.1),
  y=c(1.25,1.75,1.25,2.75))

row.names(toy_embedding) <- c("cat","dog","car","boat")

toy_embedding <- as.matrix(toy_embedding)

tr <- data.frame(
   Center=c("cat", "car"),
   Left = c("dog", "boat"),
   Right= c("car", "dog"))

# Appends a column named "toy_embedding"
test.model(toy_embedding, tr, isemb=TRUE)
#>   Center Left Right toy_embedding
#> 1    cat  dog   car           dog
#> 2    car boat   dog           dog

# Appends a column named "ModPred" instead
test.model(toy_embedding, tr, isemb=TRUE, pred_name = "ModPred")
#>   Center Left Right ModPred
#> 1    cat  dog   car     dog
#> 2    car boat   dog     dog
```
