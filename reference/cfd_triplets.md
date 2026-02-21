# Triplet data for 36 items from Chicago Face Dataset

A list containing triplet judgments for 39 participants on a subset of
36 face images from the Chicago Face Dataset. These triplets were used
to compute embeddings of the 36 items, which appear in the accompanying
object `cfd_embeddings`.

## Usage

``` r
cfd_triplets
```

## Format

### `cfd_triplets`

A named list, each containing a dataframe with 11 columns:

- head, winner, loser:

  Integer indices for items in a given triplet.

- worker_id:

  Random identifier for each participant.

- rt:

  Response time on triplet (in miliseconds).

- Center:

  The target item.

- Left, Right:

  The option items appearing on the left and right.

- Answer:

  The option item chosen by the participant.

- sampleAlg:

  The algorithm used to sample the item.

- sampleSet:

  Which set the sampled item belongs to.

## Source

<https://www.chicagofaces.org/>

## Details

Each element of the list contains the triplet data for one participant
in the study. Rows of a dataframe correspond to a single trial. The
elements of the full list are named by the random participant ID number.

Each triplet can be sampled in one of four ways indicated by sampleAlg:

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
