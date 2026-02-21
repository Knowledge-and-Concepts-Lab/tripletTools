# Get model strength

This function assesses how well the similarities expressed in an
embedding or distance model explain the triad choices contained in vdat
by computing the distance of the furthest option divided by the sum of
both distances.

## Usage

``` r
model.strength(model, vdat, isemb = TRUE)
```

## Arguments

- model:

  An embedding model.

- vdat:

  A matrix of triplet data.

- isemb:

  Flag indicating whether model is an embedding; if FALSE, model is
  treated as a distance matrix.

## Value

Vector containing the prediction strength metric for each triplet in
`vdat`

## Details

If `isemb==FALSE` function assumes `model` is a distance matrix.

The prediction-strength metric has a floor of 0.5 (both equally distant)
and increases to approach 1.0 when one option is very close and the
other very far, that is, when the answer should be obvious. If the
embedding is good, people should make reliably consistent decisions for
triplets where this 'strength' is high and less consistent decisions
when it is low.

This measure can be especially useful when computed for validation
trials where the proportion of participants agreeing with the majority
vote on a trial has been computed. If most participants agree with the
majority decision on the triplet, this means decisions are highly
reliable across participants. If the embedding is good, such items will
also have a high prediction-strength score. Thus the correlation between
prediction strength and inter-subject agreement tells you something
about the quality of the embedding.

## Examples

``` r
emb <- cfd_embeddings[[2]] #Embedding for participant 1
trips <- cfd_triplets[[2]] #Triplets for participant 1

#Get validation trials only
vdat <- subset(trips, trips$sampleAlg=="validation")

pstrength <- model.strength(emb, vdat)
```
