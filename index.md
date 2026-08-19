# tripletTools for R

An R package for analyzing data from **triadic comparison (triplet)
tasks**: a participant sees a referent item and two options, and judges
which option is more similar to the referent. From many such judgments,
`tripletTools` estimates a similarity embedding, evaluates it, and
compares it to other representations of the same items —
language/vision-model embeddings, verbal-fluency data, category labels.

## Installation

In R 3.5 or greater:

``` r

install.packages("remotes")
remotes::install_github("Knowledge-and-Concepts-Lab/tripletTools", build_vignettes = TRUE)
```

## Quick example

``` r

library(tripletTools)

# Visualize a precomputed embedding of the bundled icon stimuli
emb <- icon_emb_group
rownames(emb) <- emb$item
plot_pics(emb[, c("dim_0", "dim_1")], icon_pics, psize = 0.04)
```

## Learn more

Start with **[Getting
Started](https://knowledge-and-concepts-lab.github.io/tripletTools/articles/tripletTools.html)**,
which walks through setup, fitting an embedding, and
evaluating/visualizing the result end to end. From there:

- **[tripletTools
  Overview](https://knowledge-and-concepts-lab.github.io/tripletTools/articles/overview_vignette.html)**
  — the broader analysis toolkit: data loading, quality checks,
  inter-subject agreement, clustering
- **[Computing Triplet
  Embeddings](https://knowledge-and-concepts-lab.github.io/tripletTools/articles/embedding_vignette.html)**
  — the full embedding pipeline, dimensionality selection,
  parallel/HTCondor execution
- **[Comparing Triplet Embeddings to Alternative
  Representations](https://knowledge-and-concepts-lab.github.io/tripletTools/articles/comparing_embeddings_vignette.html)**
  — Procrustes ceilings, classifier-based evaluation, verbal-fluency
  similarity
- **[Read Triplet
  Data](https://knowledge-and-concepts-lab.github.io/tripletTools/articles/read_data_vignette.html)**
  — file formats for bringing in your own data

Every vignette is also available from within R/RStudio
(`build_vignettes = TRUE` above), and all functions are documented in
`tripletTools_manual.pdf`.
