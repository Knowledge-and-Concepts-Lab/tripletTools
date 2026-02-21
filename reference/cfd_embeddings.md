# Individual embedding data for 36 Chicago faces

This dataset contains embedding coordinates from a triplet study using
36 face images from the Chicago Face Dataset. The faces varied in
perceived gender (male/female), race (Black/White) and emotional
expression (happy, fearful, angry). Participants were asked to just
which option face was more similar to the target face without further
instruction. Two-D embeddings were computed separately for each of 39
individual participants.

## Usage

``` r
cfd_embeddings
```

## Format

### `cfd_embeddings`

A data frame with 1,404 rows and 5 columns:

- dim_0, dim_1:

  First and second dimensions of the embedding.

- worker_id:

  Random code identifying each participant

- stimulus:

  Name of the stimulus at that embedding location.

## Source

Colon et al., in preparation.

## Details

The letters in the stimulus identifier indicate features of the
corresponding face image. The first two letters indicate race (B/W for
Black/White) and perceived gender (M/F for male/female). The last two
letters indicate emotion (HO: Happy with open mouth, A: Angry, F:
Fearful).
