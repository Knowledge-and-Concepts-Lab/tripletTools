# tripletTools Overview

## Introduction

This package is designed to help analyze and visualize results from
*triadic comparisons* (or *triplet tasks*), which are used to
characterize the structure of mental representations. In a triplet task,
a participant sees a *referent* item and two *option* items, and must
decide which option is most similar to the referent. From many such
judgments across many items and participants, one can compute a
*similarity embedding*: a low-dimensional coordinate space in which
items that are frequently judged as similar are placed nearby.

`tripletTools` does not collect data or compute embeddings — those steps
occur outside R. Instead it provides tools for:

- Loading triplet and embedding data files
- Assessing participant data quality
- Measuring inter-subject agreement on shared trials
- Visualizing embeddings
- Evaluating how well an embedding predicts held-out judgments
- Quantifying individual differences in representation
- Clustering participants by representational similarity

This vignette illustrates each of these steps using the example dataset
included with the package.

``` r
library(tripletTools)
```

------------------------------------------------------------------------

## The example dataset

The package includes three objects from a triplet study on 36 face
images drawn from the Chicago Face Dataset. The faces varied in
perceived gender (male/female), race (Black/White), and emotional
expression (happy, fearful, angry). Thirty-nine participants each judged
approximately 1,000 triplets online.

| Object           | Description                                                                            |
|------------------|----------------------------------------------------------------------------------------|
| `cfd_triplets`   | Named list of 39 data frames, one per participant, containing trial-by-trial judgments |
| `cfd_embeddings` | Named list of 39 matrices, one per participant, containing 2-D embedding coordinates   |
| `cfd_pics`       | Named list of 36 PNG images, one per stimulus face                                     |

### Triplet data

Each element of `cfd_triplets` is one participant’s trial data:

``` r
head(cfd_triplets[[1]])
#>   head winner loser worker_id   rt            Center              Left
#> 1   15      6     0     78972 8728 CFD-BM-038-007-HO CFD-BF-002-004-HO
#> 2   29     31    33     78972 9946  CFD-WM-023-015-F  CFD-WM-033-014-A
#> 3   11     28    34     78972 6598  CFD-BM-002-016-A  CFD-WM-023-012-A
#> 4   32     14    16     78972 4908  CFD-WM-033-053-F  CFD-BM-009-009-F
#> 5   24     31    28     78972 8271  CFD-WF-026-008-A  CFD-WM-033-014-A
#> 6    2     23    20     78972 8812  CFD-BF-002-022-F  CFD-WF-001-027-F
#>               Right            Answer  sampleAlg sampleSet
#> 1 CFD-BF-050-004-HO CFD-BF-050-004-HO validation     train
#> 2 CFD-WM-038-005-HO  CFD-WM-033-014-A validation     train
#> 3  CFD-WM-038-011-A  CFD-WM-023-012-A validation     train
#> 4  CFD-BM-038-017-F  CFD-BM-009-009-F validation     train
#> 5  CFD-WM-023-012-A  CFD-WM-033-014-A validation     train
#> 6  CFD-WF-020-027-F  CFD-WF-020-027-F validation     train
```

The key columns are `Center` (the referent item), `Left` and `Right`
(the two options), `Answer` (the participant’s choice), `sampleAlg` (how
the trial was sampled: `random`, `check`, or `validation`), and
`sampleSet` (whether the trial was used to fit the embedding — `train` —
or held out for testing — `test`).

### Embedding data

Each element of `cfd_embeddings` is a 36-row matrix of 2-D embedding
coordinates, with row names equal to stimulus names:

``` r
head(cfd_embeddings[[1]])
#>                       dim_0       dim_1
#> CFD-BF-002-004-HO 0.3947823  0.16756907
#> CFD-BF-002-018-A  0.4886511  0.08649993
#> CFD-BF-002-022-F  0.2059984  0.10942531
#> CFD-BF-005-005-HO 0.3141250  0.12844554
#> CFD-BF-005-020-A  0.1804924 -0.31689260
#> CFD-BF-005-022-F  0.1909470 -0.32095847
```

------------------------------------------------------------------------

## Data quality assessment

Before analyzing results it is good practice to check whether
participants engaged with the task. `get.participant.summary` produces a
per-participant summary including the number of trials completed, mean
accuracy on *check trials* (easy triplets with an obvious answer used as
an attention check), and mean log response time.

``` r
psummary <- get.participant.summary(cfd_triplets)
head(psummary)
#>   tripfile worker_id ndat         lrt      cacc  keep
#> 1    78972     78972 1012  0.77807851 1.0000000  TRUE
#> 2    78103     78103 1012  0.54139779 1.0000000  TRUE
#> 3    77827     77827 1012  0.58263855 0.9818182  TRUE
#> 4    79088     79088 1012  0.84922012 1.0000000  TRUE
#> 5    79377     79377 1012  0.27563052 0.9242424  TRUE
#> 6    80900     80900 1012 -0.09235084 0.8181818 FALSE
```

The output includes a `pass` column flagging participants who fall below
the specified thresholds (by default: at least 1,000 trials, check-trial
accuracy ≥ 0.80, mean log RT \> 0). Participants failing these criteria
should be reviewed before including their data in downstream analyses.

------------------------------------------------------------------------

## Inter-subject agreement on validation trials

A subset of trials — the *validation* trials — are drawn from a fixed
pool shared across all participants, meaning the same triplets appear in
multiple participants’ datasets. This allows us to measure inter-subject
consistency: for each validation triplet we identify the *majority vote*
(the option chosen by most participants who saw it) and the proportion
of participants who agreed with that majority.

`make.vmat` computes this from the full triplet list:

``` r
vmat <- make.vmat(cfd_triplets)

# One row per unique validation triplet
head(vmat$majority)
#>                                                 triplet          majority
#> 1   CFD-BF-002-004-HO_CFD-BF-005-020-A_CFD-BF-050-036-F  CFD-BF-050-036-F
#> 2    CFD-BF-002-022-F_CFD-WF-001-027-F_CFD-WF-020-027-F  CFD-WF-020-027-F
#> 3    CFD-BF-005-022-F_CFD-BM-002-002-F_CFD-BM-009-009-F  CFD-BM-009-009-F
#> 4   CFD-BM-002-002-F_CFD-BM-009-008-A_CFD-BM-038-007-HO  CFD-BM-009-008-A
#> 5    CFD-BM-002-016-A_CFD-WM-023-012-A_CFD-WM-038-011-A  CFD-WM-023-012-A
#> 6 CFD-BM-038-007-HO_CFD-BF-002-004-HO_CFD-BF-050-004-HO CFD-BF-050-004-HO
#>        pmaj
#> 1 0.5897436
#> 2 0.6666667
#> 3 0.7692308
#> 4 0.6153846
#> 5 0.7179487
#> 6 0.5897436
```

The `pmaj` column shows the proportion of participants who agreed with
the majority choice. Values near 1.0 indicate near-universal agreement;
values near 0.5 indicate a closely split decision.

``` r
hist(vmat$majority$pmaj,
     breaks = 10,
     main   = "Inter-subject agreement on validation trials",
     xlab   = "Proportion agreeing with majority vote",
     col    = "steelblue", border = "white")
abline(v = 0.5, lty = 2, col = "red")
```

![Distribution of inter-subject agreement on validation
trials.](overview_vignette_files/figure-html/vmat-hist-1.png)

Distribution of inter-subject agreement on validation trials.

The `bysbj` element is a participant × triplet matrix recording whether
each participant agreed with the majority vote (1), disagreed (0), or
did not see the triplet (NA). The mean across triplets gives each
participant’s overall agreement rate:

``` r
round(rowMeans(vmat$bysbj, na.rm = TRUE), 2)
#> 78972 78103 77827 79088 79377 80900 81492 81753 81157 78375 79564 81964 79666 
#>  0.83  0.67  0.75  0.67  0.75  0.67  0.67  0.75  0.50  0.75  0.50  0.50  0.67 
#> 79497 79363 77536 81416 82291 78399 78416 81182 82531 79471 81233 82327 79457 
#>  0.75  0.58  0.83  0.33  0.58  0.50  0.58  0.67  0.67  0.50  0.67  0.75  1.00 
#> 79996 77641 78808 80093 81270 79549 78864 79882 79672 79060 78383 78332 79028 
#>  0.67  0.67  0.58  0.83  0.50  0.67  0.75  0.67  0.67  0.67  0.58  0.67  0.83
```

------------------------------------------------------------------------

## Visualizing a 2-D embedding

`plot_pics` plots images as points in a scatterplot, positioned at their
embedding coordinates. This gives an immediate visual impression of how
the faces are organized in the learned similarity space.

``` r
emb1 <- cfd_embeddings[[1]]

plot_pics(emb1, cfd_pics,
          psize = 0.04,
          xlab  = "Dimension 1",
          ylab  = "Dimension 2",
          main  = "Embedding – participant 1")
```

![2-D embedding for participant 1, with face images as
points.](overview_vignette_files/figure-html/plot-emb-1.png)

2-D embedding for participant 1, with face images as points.

Faces that appear close together were frequently judged as similar to
one another by this participant.

------------------------------------------------------------------------

## Evaluating embedding quality: hold-out prediction accuracy

After computing an embedding we want to know how well it captures the
participant’s actual judgments. For each held-out (*test*) triplet we
can ask: does the embedding correctly predict which option the
participant chose? The predicted choice is whichever option is closer to
the referent in the embedding space.

`get.hoacc` returns the proportion of held-out trials for which the
embedding’s prediction matches the participant’s answer:

``` r
acc1 <- get.hoacc(cfd_embeddings[[1]], cfd_triplets[[1]])
cat("Hold-out prediction accuracy (participant 1):", round(acc1, 3), "\n")
#> Hold-out prediction accuracy (participant 1): 0.828
```

Chance performance is 0.50. Values above approximately 0.60 are
generally considered reasonable for a 2-D embedding.

`test.model` returns trial-level predictions, making it easy to inspect
specific errors or compute accuracy on any subset of trials:

``` r
result     <- test.model(cfd_embeddings[[1]], cfd_triplets[[1]])
test_rows  <- result$sampleSet == "test"
mean(result$ModPred[test_rows] == result$Answer[test_rows])
#> [1] NA
```

### Prediction strength

`model.strength` computes, for each triplet, how *decisively* the
embedding favors one option over the other. The metric is max(d1, d2) /
(d1 + d2), where d1 and d2 are the distances from the referent to each
option. It ranges from 0.5 (options equidistant from the referent) to
1.0 (one option far closer than the other).

If the embedding is well-calibrated, trials where it is most confident
should also be the trials where participants agree most strongly. We can
test this using the validation trials, for which we have an
inter-subject agreement measure:

``` r
# Validation trials for participant 1
vtrips <- subset(cfd_triplets[[1]], sampleAlg == "validation")

# Prediction strength from participant 1's embedding
pstrength <- model.strength(cfd_embeddings[[1]], vtrips)

# Locate matching inter-subject agreement values
tnames  <- make.tripnames(vtrips)
maj_idx <- match(tnames, vmat$majority$triplet)
pmaj    <- vmat$majority$pmaj[maj_idx]

# Plot the relationship
plot(pstrength, pmaj,
     xlab = "Embedding prediction strength",
     ylab = "Inter-subject agreement",
     pch  = 16, col = rgb(0, 0, 0.8, 0.4),
     main = "Strength vs. inter-subject agreement")
abline(lm(pmaj ~ pstrength), col = "red")
```

![Embedding prediction strength vs. inter-subject agreement on
validation
trials.](overview_vignette_files/figure-html/model-strength-1.png)

Embedding prediction strength vs. inter-subject agreement on validation
trials.

``` r

cat("Correlation:", round(cor(pstrength, pmaj, use = "complete.obs"), 3), "\n")
#> Correlation: 0.561
```

A positive correlation indicates that the embedding correctly identifies
which triplets have clearer, more consistent answers.

------------------------------------------------------------------------

## Individual differences: the prediction matrix

A central question in many triplet studies is whether participants
differ reliably in their representations. The *prediction matrix*
approach addresses this: we use each participant’s embedding to predict
every other participant’s held-out judgments. If individual differences
are real and systematic, a participant’s *own* embedding should predict
their judgments better than another participant’s embedding does.

`get.prediction.matrix` computes this for all pairs:

``` r
pmat <- get.prediction.matrix(cfd_embeddings, cfd_triplets)
```

The result is a 39 × 39 matrix. Entry \[i, j\] is the accuracy with
which participant i’s embedding predicts participant j’s held-out
judgments. The diagonal contains each participant’s *self-prediction*
accuracy.

``` r
cat("Mean self-prediction accuracy:  ", round(mean(diag(pmat)), 3), "\n")
#> Mean self-prediction accuracy:   0.773
cat("Mean other-prediction accuracy: ", round(mean(pmat[row(pmat) != col(pmat)]), 3), "\n")
#> Mean other-prediction accuracy:  0.645
```

`z.pred.mat` converts each diagonal entry to a z-score relative to the
other entries in its row, expressing how much better (or worse) a
participant’s own embedding predicts their data compared to other
participants’ embeddings:

``` r
zscores <- z.pred.mat(pmat)

cat("Mean z-score of self-prediction:", round(mean(zscores, na.rm = TRUE), 3), "\n")
#> Mean z-score of self-prediction: 2.358
cat("Proportion with positive z-score:", round(mean(zscores > 0, na.rm = TRUE), 3), "\n")
#> Proportion with positive z-score: 1
```

If z-scores are reliably positive across participants, this is evidence
of meaningful individual differences in the representation of the
stimulus set.

------------------------------------------------------------------------

## Representational distances between participants

`get.rep.dist` computes the pairwise *procrustes distance* between all
pairs of embeddings. Two embeddings that can be brought into
near-perfect alignment by rotation, scaling, and reflection have a low
distance; embeddings that remain dissimilar after alignment have a high
distance.

``` r
repdist <- get.rep.dist(cfd_embeddings)
```

We can cluster participants by their representational distances using
standard hierarchical clustering:

``` r
hc     <- hclust(as.dist(repdist), method = "ward.D")
clusts <- cutree(hc, k = 3)

plot(hc,
     labels = FALSE,
     main   = "Participant clustering by representational distance",
     xlab   = "", sub = "")
rect.hclust(hc, k = 3, border = c("tomato", "steelblue", "seagreen"))
```

![Participants clustered by pairwise representational
distance.](overview_vignette_files/figure-html/hclust-1.png)

Participants clustered by pairwise representational distance.

### Mean embedding per cluster

`get.group.list.mean` aligns all embeddings within each cluster and
returns a mean embedding for each group:

``` r
mn_by_clust <- get.group.list.mean(cfd_embeddings, clusts)
```

Plotting each cluster’s mean embedding shows whether different groups of
participants organized the faces in qualitatively different ways:

``` r
plot_pics(mn_by_clust[[1]], cfd_pics, psize = 0.04,
          xlab = "Dimension 1", ylab = "Dimension 2",
          main = "Cluster 1 – mean embedding")
```

![Mean 2-D embedding for cluster
1.](overview_vignette_files/figure-html/plot-cluster-1-1.png)

Mean 2-D embedding for cluster 1.

``` r
plot_pics(mn_by_clust[[2]], cfd_pics, psize = 0.04,
          xlab = "Dimension 1", ylab = "Dimension 2",
          main = "Cluster 2 – mean embedding")
```

![Mean 2-D embedding for cluster
2.](overview_vignette_files/figure-html/plot-cluster-2-1.png)

Mean 2-D embedding for cluster 2.

``` r
plot_pics(mn_by_clust[[3]], cfd_pics, psize = 0.04,
          xlab = "Dimension 1", ylab = "Dimension 2",
          main = "Cluster 3 – mean embedding")
```

![Mean 2-D embedding for cluster
3.](overview_vignette_files/figure-html/plot-cluster-3-1.png)

Mean 2-D embedding for cluster 3.

------------------------------------------------------------------------

## Prediction accuracy by cluster

If the clustering captures genuine individual differences, a
participant’s held-out judgments should be better predicted by
embeddings from within their cluster than by embeddings from other
clusters. `pacc.by.cluster` tests this directly using the prediction
matrix:

``` r
pbc <- pacc.by.cluster(pmat, clusts, samediff = TRUE)
head(pbc)
#>            self      same     other
#> 78972 0.8277512 0.6842105 0.5259171
#> 78103 0.7905759 0.6862250 0.6387435
#> 77827 0.7978723 0.7329420 0.5638298
#> 79088 0.8689320 0.7566120 0.5943905
#> 79377 0.7318436 0.6636872 0.6084307
#> 80900 0.6415929 0.6109246 0.5373648
```

Each row is one participant. The three columns give prediction accuracy
from (1) their own embedding, (2) the mean of their cluster-mates’
embeddings, and (3) the mean of participants outside their cluster.

``` r
round(colMeans(pbc), 3)
#>  self  same other 
#> 0.773 0.675 0.594
```

``` r
plot_cis(pbc,
         xvals  = 1:3,
         main   = "Prediction accuracy by cluster membership",
         ylab   = "Hold-out prediction accuracy",
         xaxt   = "n",
         ylim   = c(0.5, 0.75))
axis(1, at = 1:3, labels = c("Self", "Same cluster", "Other cluster"))
abline(h = 0.5, lty = 2, col = "grey50")
```

![Hold-out prediction accuracy: self, same cluster, and other
cluster.](overview_vignette_files/figure-html/pbc-plot-1.png)

Hold-out prediction accuracy: self, same cluster, and other cluster.

A higher mean for “same cluster” than “other cluster” indicates that
cluster membership captures something real about how participants differ
in their representations.

------------------------------------------------------------------------

## Tree visualization with images as leaves

For a richer view of the similarity structure in one participant’s
embedding, a hierarchical cluster tree with face images at the leaves
can be more informative than a 2-D scatterplot — especially for
higher-dimensional embeddings. `get.tip.coords` retrieves the tip
coordinates of a phylogram plot, allowing `plot_pics` to place images at
the correct positions.

``` r
hc_emb <- hclust(dist(cfd_embeddings[[1]]), method = "ward.D")
pt     <- ape::as.phylo(hc_emb)

plot(pt, type = "fan", show.tip.label = FALSE,
     main = "Face similarity tree – participant 1")

tip_coords <- get.tip.coords()
plot_pics(tip_coords, cfd_pics, newplot = FALSE, psize = 0.04)
```

![Similarity tree for participant 1, with face images at the
leaves.](overview_vignette_files/figure-html/tree-plot-1.png)

Similarity tree for participant 1, with face images at the leaves.

Faces on nearby branches were judged as similar by this participant.

------------------------------------------------------------------------

## Summary

The table below maps common analysis questions to the corresponding
`tripletTools` functions:

| Question                                                | Function(s)                           |
|---------------------------------------------------------|---------------------------------------|
| Did participants engage with the task?                  | `get.participant.summary`             |
| How consistent are judgments across participants?       | `make.vmat`                           |
| What does a participant’s embedding look like?          | `plot_pics`                           |
| How well does the embedding predict held-out judgments? | `get.hoacc`, `test.model`             |
| Does the embedding correctly rank triplet difficulty?   | `model.strength`                      |
| Are individual differences in representation reliable?  | `get.prediction.matrix`, `z.pred.mat` |
| How similar are two participants’ representations?      | `get.rep.dist`                        |
| Are there subgroups with similar representations?       | `get.rep.dist`, `get.group.list.mean` |
| Do cluster-mates predict each other’s data better?      | `pacc.by.cluster`, `plot_cis`         |
| How to show a full similarity tree with images?         | `get.tip.coords`, `plot_pics`         |
