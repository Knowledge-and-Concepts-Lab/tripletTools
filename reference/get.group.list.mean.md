# Get group list mean

From a list of embeddings and a vector indicating to which group each
embedding belongs, this function aligns embeddings within each group,
then computes the mean embedding across members of the group.

## Usage

``` r
get.group.list.mean(elist, grps)
```

## Arguments

- elist:

  List of embeddings.

- grps:

  Vector indicating to which group each individual in `elist` belongs.
  Elements must be in the same order as in elist.

## Value

List containing mean embedding for each group.

## Details

This function is useful for visualizing the mean embedding for different
groups without having to recompute it from scratch. Note that the
average of the aligned embeddings returned by this function will
necessarily be the same as what is found if the embeddings *are*
computed from scratch from the same participants.

## Examples

``` r
repdist <- get.rep.dist(icon_emb_ind) #Representational distances
hc <- hclust(as.dist(repdist), method = "ward.D") #Cluster tree
clusts <- cutree(hc, 2) #Cut into 2 clusters

mn.by.clust <- get.group.list.mean(icon_emb_ind, clusts)
plot_pics(mn.by.clust[[1]], icon_pics)
```
