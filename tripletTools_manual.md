# tripletTools: Reference Manual

**Version 0.1.0** **Author:** Timothy Rogers **License:** MIT

------------------------------------------------------------------------

## Table of Contents

| Function / Dataset                                | Title                                                           |
|---------------------------------------------------|-----------------------------------------------------------------|
| [align.embeddings](#alignembeddings)              | Align embeddings across participants                            |
| [cfd_embeddings](#cfd_embeddings)                 | Individual embedding data for 36 Chicago faces *(dataset)*      |
| [cfd_pics](#cfd_pics)                             | Chicago Face Dataset pictures *(dataset)*                       |
| [cfd_triplets](#cfd_triplets)                     | Triplet data for 36 items from Chicago Face Dataset *(dataset)* |
| [get.combined](#getcombined)                      | Get combined data                                               |
| [get.group.list.mean](#getgrouplistmean)          | Get group list mean                                             |
| [get.hoacc](#gethoacc)                            | Get hold-out prediction accuracy                                |
| [get.nearest.k](#getnearestk)                     | Get nearest k                                                   |
| [get.participant.summary](#getparticipantsummary) | Get participant summary                                         |
| [get.prediction.matrix](#getpredictionmatrix)     | Get prediction matrix                                           |
| [get.raster.from.png](#getrasterfrompng)          | Get raster from PNG                                             |
| [get.rep.dist](#getrepdist)                       | Get representational distances                                  |
| [get.tip.coords](#gettipcoords)                   | Get tip coordinates                                             |
| [make.tripnames](#maketripnames)                  | Make triplet names                                              |
| [make.vmat](#makevmat)                            | Make validation matrix                                          |
| [model.strength](#modelstrength)                  | Get model strength                                              |
| [pacc.by.cluster](#paccbycluster)                 | Prediction accuracy by cluster                                  |
| [plot_cis](#plot_cis)                             | Plot column means and confidence intervals                      |
| [plot_pics](#plot_pics)                           | Plot pictures in a scatterplot                                  |
| [strsplit1](#strsplit1)                           | Split a string                                                  |
| [test.model](#testmodel)                          | Test embedding model predictions                                |
| [z.pred.mat](#zpredmat)                           | Z-score prediction matrix                                       |

------------------------------------------------------------------------

## align.embeddings

**Align embeddings across participants**

### Description

This function takes a list of embeddings, one per participant, and
procrustes-aligns each to a reference embedding.

### Usage

``` r
align.embeddings(emb, scl = TRUE, baseno = 1)
```

### Arguments

| Argument | Description                                               |
|----------|-----------------------------------------------------------|
| `emb`    | List of embeddings; each element is one participant.      |
| `scl`    | Flag indicating whether alignment should allow scaling.   |
| `baseno` | Integer indicating which list element to use as the base. |

### Details

Each element of the list should contain embedding data from one
participant, as returned by the function `get.combined`. Each embedding
must contain the same items in the same order, and must be of the same
dimension. The function will procrustes-align each participant’s
embedding to the base participant, specified by the `baseno` argument.
The procrustes alignment permits rotation, translation, scaling and
reflection.

### Value

A list with each participant’s embedding aligned to the base embedding.

### Examples

``` r
# Example data for subject 1
s1 <- data.frame(
      x = c(1:10) + runif(10)/10,
      y = c(1:10) + runif(10)/10
      )

s2 <- s1 * 2 + 4   # Double and shift s1 data
s2[,1] <- -1 * s2[,1]   # Reflect along one dimension

unaligned <- list(s1, s2)
aligned <- align.embeddings(unaligned)
```

------------------------------------------------------------------------

## cfd_embeddings

**Individual embedding data for 36 Chicago faces** *(dataset)*

### Description

This dataset contains embedding coordinates from a triplet study using
36 face images from the Chicago Face Dataset. The faces varied in
perceived gender (male/female), race (Black/White) and emotional
expression (happy, fearful, angry). Participants were asked to judge
which option face was more similar to the target face without further
instruction. Two-dimensional embeddings were computed separately for
each of 39 individual participants.

### Usage

``` r
cfd_embeddings
```

### Format

A data frame with 1,404 rows and 5 columns:

| Column           | Description                                      |
|------------------|--------------------------------------------------|
| `dim_0`, `dim_1` | First and second dimensions of the embedding.    |
| `worker_id`      | Random code identifying each participant.        |
| `stimulus`       | Name of the stimulus at that embedding location. |

### Details

The letters in the stimulus identifier indicate features of the
corresponding face image. The first two letters indicate race (B/W for
Black/White) and perceived gender (M/F for male/female). The last two
letters indicate emotion (HO: Happy with open mouth, A: Angry, F:
Fearful).

### Source

Colon et al., in preparation.

------------------------------------------------------------------------

## cfd_pics

**Chicago Face Dataset pictures** *(dataset)*

### Description

This dataset contains PNG format images of 36 items from the Chicago
Face Dataset. These are the stimuli used in the demo experiment included
as part of this package.

### Usage

``` r
cfd_pics
```

### Format

A named list with 36 elements, each containing one face image.

### Details

Each item is named with the corresponding image file name. The first two
letters of the name indicate the perceived gender (F/M) and race (B/W),
respectively. The final letter(s) indicate the intended emotional
expression (HO: Happy open-mouth, F: Fearful, A: Angry).

### Source

<https://www.chicagofaces.org/>

------------------------------------------------------------------------

## cfd_triplets

**Triplet data for 36 items from Chicago Face Dataset** *(dataset)*

### Description

A list containing triplet judgments for 39 participants on a subset of
36 face images from the Chicago Face Dataset. These triplets were used
to compute embeddings of the 36 items, which appear in the accompanying
object `cfd_embeddings`.

### Usage

``` r
cfd_triplets
```

### Format

A named list, each element containing a dataframe with 11 columns:

| Column                    | Description                                       |
|---------------------------|---------------------------------------------------|
| `head`, `winner`, `loser` | Integer indices for items in a given triplet.     |
| `worker_id`               | Random identifier for each participant.           |
| `rt`                      | Response time on triplet (in milliseconds).       |
| `Center`                  | The target item.                                  |
| `Left`, `Right`           | The option items appearing on the left and right. |
| `Answer`                  | The option item chosen by the participant.        |
| `sampleAlg`               | The algorithm used to sample the item.            |
| `sampleSet`               | Which set the sampled item belongs to.            |

### Details

Each element of the list contains the triplet data for one participant
in the study. Rows of a dataframe correspond to a single trial. The
elements of the full list are named by the random participant ID number.

Each triplet can be sampled in one of four ways indicated by
`sampleAlg`:

1.  *random*: Sampled randomly with uniform probability from all
    triplets.
2.  *validation*: Sampled randomly from a fixed, pre-specified set of
    possible triplets.
3.  *check*: Sampled from a small set of items where the answer is
    obvious, used to check attention and data quality.
4.  *adaptive*: Sampled according to some adaptive sampling algorithm.

The column `sampleSet` indicates how the triplet is to be used in
computing and evaluating embeddings:

1.  *train*: Triplets used to fit embedding.
2.  *test*: Triplets held out from training, used to evaluate embedding
    quality.
3.  NA: Triplets used for checking attention / data quality.

Validation trials can be used to measure the extent of inter-subject
agreement: since these are drawn from a common pool, these triplets will
appear repeatedly across participants. Thus for each such triplet one
can compute the majority vote across participants who received the
triplet, and the proportion of those participants who agree with the
majority vote. This gives an estimate of how consistent judgments are
across participants.

------------------------------------------------------------------------

## get.combined

**Get combined data**

### Description

This function reads a triplet or embedding data file containing data
from multiple participants, returning a named list with each element
containing data from one participant.

### Usage

``` r
get.combined(fname, eflag = FALSE)
```

### Arguments

| Argument | Description                                                   |
|----------|---------------------------------------------------------------|
| `fname`  | Path to and name of the data file.                            |
| `eflag`  | Flag indicating whether data are embeddings; default `FALSE`. |

### Details

Data files must be in CSV format with column names in the first line.
The function assumes participant identifier labels are included in a
field called `worker_id`. If the data are embeddings, the file must
contain column names called `dim_x` where `x` is the dimension number.
Embedding data must also include a column named `item` that indicates
the item embedded at each row. The function will use this column to set
row names for each dataframe. The list elements will be labelled by the
`worker_id` value.

Use this function to read in combined (across subjects) triplet data
files (with `eflag=FALSE`) or embedding files (with `eflag=TRUE`).

### Value

A named list, each element being a dataframe containing one
participant’s data.

### Examples

``` r
fpath <- system.file("extdata", "cfd36_embeddings_individual.csv", package = "tripletTools")

embeddings <- get.combined(fpath, eflag = TRUE)

head(embeddings[[1]])
```

------------------------------------------------------------------------

## get.group.list.mean

**Get group list mean**

### Description

From a list of embeddings and a vector indicating to which group each
embedding belongs, this function aligns embeddings within each group,
then computes the mean embedding across members of the group.

### Usage

``` r
get.group.list.mean(elist, grps)
```

### Arguments

| Argument | Description                                                                                                            |
|----------|------------------------------------------------------------------------------------------------------------------------|
| `elist`  | List of embeddings.                                                                                                    |
| `grps`   | Vector indicating to which group each individual in `elist` belongs. Elements must be in the same order as in `elist`. |

### Details

This function is useful for visualizing the mean embedding for different
groups without having to recompute it from scratch. Note that the
average of the aligned embeddings returned by this function will
necessarily be the same as what is found if the embeddings *are*
computed from scratch from the same participants.

### Value

List containing mean embedding for each group.

### Examples

``` r
repdist <- get.rep.dist(cfd_embeddings)         # Representational distances
hc <- hclust(as.dist(repdist), method = "ward.D")  # Cluster tree
clusts <- cutree(hc, 4)                          # Cut into 4 clusters

mn.by.clust <- get.group.list.mean(cfd_embeddings, clusts)
plot_pics(mn.by.clust[[1]], cfd_pics)
```

------------------------------------------------------------------------

## get.hoacc

**Get hold-out prediction accuracy**

### Description

This function computes embedding prediction accuracy on held-out items.

### Usage

``` r
get.hoacc(em, td, trialtype = "test", isemb = TRUE)
```

### Arguments

| Argument    | Description                                                                                                  |
|-------------|--------------------------------------------------------------------------------------------------------------|
| `em`        | Embedding or distance matrix for generating predictions.                                                     |
| `td`        | Dataframe containing triplet data to be evaluated.                                                           |
| `trialtype` | Type of trial to be evaluated; defaults to `"test"`.                                                         |
| `isemb`     | When `TRUE`, `em` is a matrix of embedding coordinates; when `FALSE`, it is assumed to be a distance matrix. |

### Details

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

### Value

A real-valued number indicating the proportion of trials (of the
indicated type) for which the prediction was correct.

### Examples

``` r
m <- data.frame(
  x = c(1, 1.1, 2, 2.1),
  y = c(1.25, 1.75, 1.25, 1.75))

row.names(m) <- c("cat", "dog", "car", "boat")
m <- as.matrix(m)

tr <- data.frame(
   Center    = c("cat",  "car",   "dog", "boat"),
   Left      = c("dog",  "boat",  "car", "cat"),
   Right     = c("car",  "dog",   "boat","car"),
   Answer    = c("dog",  "boat",  "car", "car"),
   sampleSet = c("test", "test",  "test","test"))

get.hoacc(m, tr, isemb = TRUE)
```

------------------------------------------------------------------------

## get.nearest.k

**Get nearest k**

### Description

This function takes a distance matrix and an item name and returns the
`k` nearest neighbors to the specified item.

### Usage

``` r
get.nearest.k(dmat, item, k = 5)
```

### Arguments

| Argument | Description                                                              |
|----------|--------------------------------------------------------------------------|
| `dmat`   | Data matrix; rows must be named.                                         |
| `item`   | String indicating the item for which nearest neighbors will be returned. |
| `k`      | How many neighbors to return.                                            |

### Details

`dmat` must be a matrix with named rows, and `item` must match the name
of one row.

This function is useful for understanding local similarity structure in
a higher-dimensional embedding, and for creating a k-nearest-neighbor
graph of such structure.

### Value

A character vector containing the `k` nearest neighbors in order of
proximity to the target item.

### Examples

``` r
emb <- cfd_embeddings[[10]]         # Embedding for participant 10
fdists <- as.matrix(dist(emb))       # Compute pairwise distance matrix
target <- "CFD-BF-002-004-HO"       # Name of target item

# Return 5 items nearest to target:
get.nearest.k(fdists, target, 5)
```

------------------------------------------------------------------------

## get.participant.summary

**Get participant summary**

### Description

This function takes a list of triplet data of the kind returned by
`get.combined` and from it generates a dataframe summarizing information
about each participant in the study.

### Usage

``` r
get.participant.summary(d, irange = NULL, mintrial = 1000, accthresh = 0.8, rtthresh = 0)
```

### Arguments

| Argument    | Description                                                              |
|-------------|--------------------------------------------------------------------------|
| `d`         | List of triplet data. Each element is data from one participant.         |
| `irange`    | Vector indicating which elements of the list to include. Default is all. |
| `mintrial`  | Minimum number of trials needed to count as a complete record.           |
| `accthresh` | Accuracy threshold for check trials to pass quality check.               |
| `rtthresh`  | Threshold of log RT to pass quality check.                               |

### Details

The summary will include participant ID, number of completed trials,
mean accuracy on check trials, and mean log(RT) across all trials. The
arguments `accthresh` and `rtthresh` set criteria for assessing the
participant’s data quality. A mean log RT of 0 or less means the
participant was responding in under one second on average, usually too
fast for data to be real. Chance responding will yield an accuracy of
0.5 on check trials, so a threshold of 0.8 means the participant was
likely guessing on at least 40 percent of trials.

This function assumes standard triplet data naming conventions for
column names.

### Value

Data frame containing information about each participant in the study.

### Examples

``` r
# Path to example triplet data
fpath <- system.file("extdata", "cfd36_triplets_individual.csv", package = "tripletTools")

# Read the data
trips <- get.combined(fpath)

# Compute summary
part.summary <- get.participant.summary(trips)

head(part.summary)
```

------------------------------------------------------------------------

## get.prediction.matrix

**Get prediction matrix**

### Description

This function takes a list of embeddings and a matched list of triplet
data and uses each embedding to predict responses on each triplet
dataset, returning the mean accuracy as a matrix.

### Usage

``` r
get.prediction.matrix(elist, tlist, ttype = "test")
```

### Arguments

| Argument | Description                                                |
|----------|------------------------------------------------------------|
| `elist`  | Named list of embeddings.                                  |
| `tlist`  | Named list of triplet data.                                |
| `ttype`  | Type of trial to evaluate on; defaults to `"test"` trials. |

### Details

Elements of the embedding and triplet lists should be named with the
participant ID, as in the format returned by `get.combined`. Ideally
these lists will contain the same participants in the same order. The
function expects files that conform to naming conventions. It first
extracts trials of the indicated type, then uses `get.hoacc` to compute
the proportion of items for which the embedding predicts the correct
response. It loops through all embeddings and datasets, returning a
matrix of the corresponding prediction accuracies.

Assuming the two lists contain the same participants in the same order,
the matrix diagonal will indicate how well a participant’s own embedding
predicts their decisions on the test items (typically hold-out items not
used to compute the embedding).

### Value

A matrix. Each row is an embedding, each column a triplet dataset.
Entries indicate how accurately the embedding predicts the triplet data
for the trial type indicated.

### Examples

``` r
embpath <- system.file("extdata", "cfd36_embeddings_individual.csv", package = "tripletTools")
tripath <- system.file("extdata", "cfd36_triplets_individual.csv",   package = "tripletTools")

# Get first five participants
embs  <- get.combined(embpath, eflag = TRUE)[1:5]
trips <- get.combined(tripath, eflag = FALSE)[1:5]

pmat <- get.prediction.matrix(embs, trips, ttype = "test")
pmat
```

------------------------------------------------------------------------

## get.raster.from.png

**Get raster from PNG**

### Description

This function reads a PNG file and converts it to a raster object with a
transparent background for plotting.

### Usage

``` r
get.raster.from.png(f)
```

### Arguments

| Argument | Description             |
|----------|-------------------------|
| `f`      | Filename for PNG image. |

### Details

When plotting line-drawings as points on a scatterplot (using
`plot_pics` for instance), it can be useful to keep the line drawing
background transparent and to be able to control the color in which the
image is plotted. Converting PNGs to rasters allows this functionality.
This function converts the PNG to a raster object; setting the `pc`
argument in `plot_pics` then controls the color when plotting the image.

------------------------------------------------------------------------

## get.rep.dist

**Get representational distances**

### Description

Given a list of embeddings, this function computes the procrustes
distance between each pair and returns this as a distance matrix.

### Usage

``` r
get.rep.dist(elist, rootflag = TRUE)
```

### Arguments

| Argument   | Description                                          |
|------------|------------------------------------------------------|
| `elist`    | List of embeddings.                                  |
| `rootflag` | Compute square root of distance? Defaults to `TRUE`. |

### Details

Each element of the list should contain a matrix of embedding
coordinates from one participant. Each embedding should contain the same
items in the same order, and should be of the same dimension.

By default the distance metric is the procrustes equivalent of Pearson’s
correlation, that is `1 - sqrt(1 - ss)` where `ss` is the normalized sum
of squares from the aligned embeddings. If `rootflag=FALSE`, the
normalized sum of squares is used as the distance metric.

### Value

A matrix of distances between each pair of embeddings.

### Examples

``` r
# Subject 1 data
s1 <- matrix(
      c(1,1, 2,2, 3,3, 4,4, 5,5), 5, 2, byrow = TRUE)

# Subject 2 is a noisy version of subject 1
s2 <- s1 + runif(10) / 10

# Subject 3 is different
s3 <- matrix(
      c(1,2, 3,4, 4,3, 2,1, 5,2), 5, 2, byrow = TRUE)

slist <- list(s1, s2, s3)
sdist <- get.rep.dist(slist)
head(sdist)
```

------------------------------------------------------------------------

## get.tip.coords

**Get tip coordinates**

### Description

After generating a phylogram plot, this function returns the coordinates
of the tree tips on the plotting surface, useful for plotting images or
other symbols at the ends of the tree plot.

### Usage

``` r
get.tip.coords()
```

### Details

The `phylogram` plot type from the `ape` package invisibly stores the
tip coordinates of the plot. This function retrieves them and returns
them as a matrix useful for adding symbols or images to the leaves of
the tree.

### Value

A matrix of x, y coordinates indicating the locations of the tips of the
phylogram.

### Examples

``` r
# Make a distance matrix
dmat <- matrix(
        c(1, 1, 1, 0, 0, 0,
          1, 1, 1, 0, 0, 0,
          1, 1, 1, 0, 0, 0,
          0, 0, 0, 1, 1, 1,
          0, 0, 0, 1, 1, 1,
          0, 0, 0, 1, 1, 1), 6, 6)

dmat <- dmat + matrix(runif(36)/2, 6, 6)  # Add noise

hc    <- stats::hclust(stats::dist(dmat))
pt    <- ape::as.phylo(hc)
clusts <- stats::cutree(hc, 2)

# Plot with no tip labels, then add colored points
plot(pt, show.tip.label = FALSE)
points(get.tip.coords(), pch = 16, col = c("orange", "blue")[clusts])
```

------------------------------------------------------------------------

## make.tripnames

**Make triplet names**

### Description

This function creates a unique name for each triplet appearing in a
triplet data frame.

### Usage

``` r
make.tripnames(tripdat)
```

### Arguments

| Argument  | Description                                                               |
|-----------|---------------------------------------------------------------------------|
| `tripdat` | A data frame containing triplet data; must conform to naming conventions. |

### Details

This function is useful for finding responses to a given triplet, which
is especially important when computing within- and between-participant
consistency on validation trials.

### Value

A character vector containing the unique triplet name for each trial in
the triplet dataframe.

### Examples

``` r
trips  <- cfd_triplets[[10]]      # Triplet data for participant 10
tnames <- make.tripnames(trips)   # Make triplet names
tnames[1:5]                       # Names of first five triplets
```

------------------------------------------------------------------------

## make.vmat

**Make validation matrix**

### Description

This function uses the validation trials from triplet data to construct
a subject-by-trial matrix of judgments on these items.

### Usage

``` r
make.vmat(triplist)
```

### Arguments

| Argument   | Description                                                                                                                                       |
|------------|---------------------------------------------------------------------------------------------------------------------------------------------------|
| `triplist` | Named list whose elements each contain triplet data from one participant. Names should be participant identifiers, as returned by `get.combined`. |

### Details

Each validation triplet is identified with a unique code of the kind
generated by `make.tripnames`, which indicates the target word and the
two options with the options ordered alphabetically.

Where a participant judged a particular validation triplet the entries
of `bysbj` will indicate the proportion of times the participant’s
decision agreed with the majority vote. (In most cases this will be 0 or
1 since participants usually judge a validation triplet only once;
however in some studies the same validation trials are repeated to
evaluate self-consistency.) Where a participant did not judge a given
triplet, the entry in `bysbj` will be `NA`.

### Value

Named list with two elements. `majority` is a matrix with one row per
validation triplet, reporting the winning choice and proportion of
participants who selected it. `bysbj` is a matrix indicating, for each
participant (rows) and validation triplet (columns), the choice the
participant made.

### Examples

``` r
vmat <- make.vmat(cfd_triplets)
vmat$majority
```

------------------------------------------------------------------------

## model.strength

**Get model strength**

### Description

This function assesses how well the similarities expressed in an
embedding or distance model explain the triad choices contained in
`vdat` by computing the distance of the furthest option divided by the
sum of both distances.

### Usage

``` r
model.strength(model, vdat, eflag = TRUE)
```

### Arguments

| Argument | Description                                    |
|----------|------------------------------------------------|
| `model`  | An embedding model.                            |
| `vdat`   | A matrix of triplet data.                      |
| `eflag`  | Flag indicating whether model is an embedding. |

### Details

If `eflag==FALSE` the function assumes `model` is a distance matrix.

The prediction-strength metric has a floor of 0.5 (both options equally
distant) and increases to approach 1.0 when one option is very close and
the other very far, that is, when the answer should be obvious. If the
embedding is good, people should make reliably consistent decisions for
triplets where this ‘strength’ is high and less consistent decisions
when it is low.

This measure can be especially useful when computed for validation
trials where the proportion of participants agreeing with the majority
vote on a trial has been computed. If most participants agree with the
majority decision on the triplet, this means decisions are highly
reliable across participants. If the embedding is good, such items will
also have a high prediction-strength score. Thus the correlation between
prediction strength and inter-subject agreement tells you something
about the quality of the embedding.

### Value

Vector containing the prediction strength metric for each triplet in
`vdat`.

### Examples

``` r
emb   <- cfd_embeddings[[2]]   # Embedding for participant 2
trips <- cfd_triplets[[2]]     # Triplets for participant 2

# Get validation trials only
vdat <- subset(trips, trips$sampleAlg == "validation")

pstrength <- model.strength(emb, vdat)
```

------------------------------------------------------------------------

## pacc.by.cluster

**Prediction accuracy by cluster**

### Description

This function computes how well a participant’s held-out judgments are
predicted by their own embedding and embeddings from members of the same
or other clusters.

### Usage

``` r
pacc.by.cluster(pacc, clusts, samediff = TRUE)
```

### Arguments

| Argument   | Description                                                                                                                                                                                                |
|------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `pacc`     | Participant-by-participant matrix of predictive accuracies of the kind returned by `get.prediction.matrix`.                                                                                                |
| `clusts`   | Vector indicating the cluster membership for each participant in `pacc`.                                                                                                                                   |
| `samediff` | If `TRUE`, returns mean prediction accuracy for participants in the same cluster vs. mean from those in a different cluster. Otherwise returns mean prediction accuracy from participants in each cluster. |

### Details

Participants can be clustered based on their pairwise representational
distances as returned by `get.rep.dist`. This function will then compute
how well, on average, embeddings within a cluster predict each
participant’s held-out (test) judgments. It also returns how well the
participant’s own embedding predicts their held-out judgments. If
clusters are useful, the participant’s judgments should be
better-predicted by their cluster-mates than by non-cluster-mates. If
cluster-mates all share the same embedding, same-cluster prediction
should be as good as own-embedding prediction.

The first column of the returned matrix is always prediction accuracy
from the participant’s own embedding. If `samediff==TRUE` the returned
matrix will include mean prediction accuracy from the participant’s own
cluster and from all participants not in the same cluster. If `FALSE`,
the returned matrix will include one column per cluster, and entries
will indicate mean prediction accuracy from the embeddings in that
cluster.

### Value

A participant-by-cluster matrix indicating the mean accuracy predicting
each participant’s judgments from embeddings in each cluster.

### Examples

``` r
repdist <- get.rep.dist(cfd_embeddings)                   # Representational distances
hc      <- hclust(as.dist(repdist), method = "ward.D")
clusts  <- cutree(hc, 3)                                  # Cut tree to yield 3 clusters

pacc <- get.prediction.matrix(cfd_embeddings, cfd_triplets)  # Prediction matrix
pbc  <- pacc.by.cluster(pacc, clusts, samediff = TRUE)

colMeans(pbc)
```

------------------------------------------------------------------------

## plot_cis

**Plot column means and confidence intervals**

### Description

This function computes the mean and 95% confidence intervals of each
column in `d` and plots these either as a line plot with a transparent
ribbon (default) or as a barplot.

### Usage

``` r
plot_cis(d, barflag = FALSE, newflag = TRUE, xvals = NULL, rgbvec = c(0, 0, 1), ...)
```

### Arguments

| Argument  | Description                                                         |
|-----------|---------------------------------------------------------------------|
| `d`       | A matrix of numerical data.                                         |
| `barflag` | Flag indicating whether a barplot is desired.                       |
| `newflag` | Should a new plot be generated? Default `TRUE`.                     |
| `xvals`   | Vector of x values equal in length to the number of columns in `d`. |
| `rgbvec`  | Vector of red, green, blue proportions.                             |
| `...`     | Other graphical parameters.                                         |

### Value

Invisibly returns a matrix of column means and 95% confidence intervals.

### Examples

``` r
x <- matrix(c(1:12), 3, 4)
plot_cis(x)
```

------------------------------------------------------------------------

## plot_pics

**Plot pictures in a scatterplot**

### Description

This function plots a list of PNG or raster images as the points in a
scatterplot.

### Usage

``` r
plot_pics(md, plist, x = 1, y = 2, pr = 1, pc = NULL, psize = 0.05, newplot = TRUE, ...)
```

### Arguments

| Argument  | Description                                                                            |
|-----------|----------------------------------------------------------------------------------------|
| `md`      | Matrix of data indicating where each image is to be plotted.                           |
| `plist`   | List of PNG or raster images.                                                          |
| `x`       | Which column of the matrix should be used for x-axis position.                         |
| `y`       | Which column of the matrix should be used for y-axis position.                         |
| `pr`      | Proportion of items to be plotted, OR vector indicating which items should be plotted. |
| `pc`      | If images are rasters, what color should they be plotted in?                           |
| `psize`   | Plot size for each image as a proportion of the plotting surface.                      |
| `newplot` | Should a new plot be generated? If `FALSE`, images are added to the current plot.      |
| `...`     | Other graphical parameters.                                                            |

### Details

The number of rows in the data matrix must be equal to the length of the
list containing the images to be plotted. Each row corresponds to one
image; thus the first image in the list will be plotted at the
coordinates in row 1 of the data matrix.

When `newplot=FALSE` the images will be added as points to the existing
plot. When used with `get.tip.coords` this can add images to the tips of
phylogram plots, an effective way to visualize structure in embeddings
with more than two or three dimensions.

When there are many images, they often clutter the plot, making it hard
to see structure. You can control the proportion of images shown by
setting `pr` to a value smaller than 1.0. In this case, a random sample
of images will be plotted.

If images are line-drawings and are loaded as rasters rather than PNGs,
setting the plot color `pc` will control the color the image is
displayed in. This can be specified as a single value for all images or
as a vector of colors; if a vector, each element sets the plot color for
one image. This can be useful for displaying other data in the plot,
such as the gender of the participant who produced the drawing.

### Value

Generates a plot or adds images to an existing plot.

### Examples

``` r
# Plot a 2D embedding as a scatterplot using images instead of points:
emb <- cfd_embeddings[[1]]   # Get embedding from first participant
plot_pics(emb, cfd_pics, psize = 0.03)

# Plot the same data as a hierarchical cluster plot with images as leaves:
hc <- stats::hclust(dist(emb), method = "ward.D")
pt <- ape::as.phylo(hc)

plot(pt, type = "fan", show.tip.label = FALSE)
tip_coords <- get.tip.coords()
plot_pics(tip_coords, cfd_pics, newplot = FALSE)
```

------------------------------------------------------------------------

## strsplit1

**Split a string**

### Description

Split a string.

### Usage

``` r
strsplit1(x, split)
```

### Arguments

| Argument | Description                          |
|----------|--------------------------------------|
| `x`      | A character vector with one element. |
| `split`  | What to split on.                    |

### Value

A character vector.

### Examples

``` r
x <- "alfa,bravo,charlie,delta"
strsplit1(x, split = ",")
```

------------------------------------------------------------------------

## test.model

**Test embedding model predictions**

### Description

This function generates predicted responses on a set of triplet items
given an embedding of the items, and appends the model prediction as an
additional column named `ModPred` to the triplet data file.

### Usage

``` r
test.model(m, vdat, isemb = TRUE)
```

### Arguments

| Argument | Description                                                                                                                                 |
|----------|---------------------------------------------------------------------------------------------------------------------------------------------|
| `m`      | An embedding of the stimuli or matrix of distances among stimuli. Rows must have names that correspond with the triplet data.               |
| `vdat`   | Data frame containing triplet data. Must include columns named `Center`, `Left`, and `Right`, and names here must match row names of model. |
| `isemb`  | Is model an embedding? If `TRUE` (default), compute Euclidean distance matrix; otherwise treat model as the distance matrix.                |

### Details

The returned object will be a data frame with an added field `ModPred`
that contains the predicted response for the triplet given the
embedding. This response will be whichever of the two choice items
(`Left` or `Right`) has the smallest Euclidean distance to the target
item (`Center`) in the embedding space.

If the triplet dataframe also includes a field labelled `Answer` that
contains the true, human-generated answer for the triplet, then the
model predictions can be easily converted to a proportion correct score
as follows:

``` r
mean(output$ModPred == output$Answer)
```

where `output` is the dataframe returned by the function.

### Value

Returns the triplet dataframe with the column `ModPred` added, which
contains the predicted triplet response given the embedding or distance
matrix.

### Examples

``` r
m <- data.frame(
  x = c(1, 1.1, 2, 2.1),
  y = c(1.25, 1.75, 1.25, 2.75))

row.names(m) <- c("cat", "dog", "car", "boat")
m <- as.matrix(m)

tr <- data.frame(
   Center = c("cat", "car"),
   Left   = c("dog", "boat"),
   Right  = c("car", "dog"))

test.model(m, tr, isemb = TRUE)
```

------------------------------------------------------------------------

## z.pred.mat

**Z-score prediction matrix**

### Description

This function takes a matrix of predictive accuracies as produced by
`get.prediction.matrix` and returns, for each subject, a z-score
indicating how predictive accuracy from a subject’s own embedding
relates to those from other subjects.

### Usage

``` r
z.pred.mat(pmat)
```

### Arguments

| Argument | Description                                                                                |
|----------|--------------------------------------------------------------------------------------------|
| `pmat`   | An embedding-to-triplet prediction matrix of the kind returned by `get.prediction.matrix`. |

### Details

The matrix diagonal must contain accuracies for each participant’s own
embedding when predicting their held-out triplet judgments. These
diagonal values will be z-scored against the distribution formed by all
other accuracies in the row, which reflect accuracies of *other*
embeddings predicting that same participant’s triplet data.

If embeddings reflect true, reliable individual differences, a
participant’s own embedding should predict their held-out judgments
better than does another random participant from the matrix. In this
case the z-scored self-prediction accuracy will be positive. If the
z-score is reliably positive across the whole group of participants,
this indicates reliable individual differences in representation.

### Value

The predictive accuracy of each participant’s embedding in predicting
their own triplet decisions relative to the accuracy of other embeddings
in the matrix, computed as a z-score.

### Examples

``` r
# Random prediction matrix
pmat <- matrix(runif(25), 5, 5)

# Diagonal relatively high
diag(pmat) <- 1 - runif(5)/10

# Z-score diagonal relative to other entries
z.pred.mat(pmat)
```

------------------------------------------------------------------------

*Generated from tripletTools v0.1.0 .Rd documentation files.*
