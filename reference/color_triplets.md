# Triplet data for 58 color patches

A list containing triplet similarity judgments from 46 participants on
58 color patches spanning color space. Participants judged which of two
option patches was more similar in color to a reference patch. These
triplets were used to compute embeddings of the 58 patches separately
for each participant (`color_emb_ind`) as well as a single group
embedding (`color_emb_group`).

## Usage

``` r
color_triplets
```

## Format

### `color_triplets`

A named list, each containing a dataframe with 11 columns:

- head, winner, loser:

  Integer indices for items in a given triplet.

- worker_id:

  Random identifier for each participant.

- rt:

  Response time on triplet (in milliseconds).

- Center:

  The target item, given as a hex color code (e.g. `"#5E2B3A"`).

- Left, Right:

  The option items appearing on the left and right, same coding.

- Answer:

  The option item chosen by the participant.

- sampleAlg:

  The algorithm used to sample the item.

- sampleSet:

  Which set the sampled item belongs to.

## Source

Zimnicki et al., presented at the Annual Meeting of the Cognitive
Science Society. <https://escholarship.org/uc/item/8778p3t3>

## Details

Each element of the list contains the triplet data for one participant
in the study. Rows of a dataframe correspond to a single trial. The
elements of the full list are named by the random participant ID number.

Item codes (`Center`/`Left`/`Right`/`Answer`) are hex color strings,
which also serve directly as plotting colors for the corresponding patch
(see `color_lab`).

Each triplet can be sampled in one of three ways indicated by sampleAlg:

1.  *random*: Sampled randomly with uniform probability from all
    triplets.

2.  *validation*: Sampled randomly from a fixed, pre-specified set of
    possible triplets.

3.  *check*: Sampled from a small set of items where the answer is
    obvious, used to check attention and data quality.

The column `sampleSet` indicates how the triplet is to be used in
computing and evaluating embeddings (`"train"`/`"test"`; `NA` for check
trials).
