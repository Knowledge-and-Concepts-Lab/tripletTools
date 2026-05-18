# Individual embedding data for 32 icon images of faces and buildings

This dataset contains embedding coordinates from a triplet study using
32 icon images showing faces and buildings. All stimuli vary in age
(old/young) and time (day/night). Faces also vary in gender and race;
places vary in size and kind (house/church). Six participants were asked
to judge which option was more similar to the referent without further
instruction. Three-D embeddings were computed separately for each
participant.

## Usage

``` r
icon_emb_ind
```

## Format

### `icon_emb_ind`

A list with six elements, each containing an embedding from one person.
The embedding is a data frame object with 32 rows (items) and six
columns as follows:

- dim_0, dim_1, dim_2:

  First, second and third dimensions of the embedding.

- worker_id:

  Random code identifying each participant

- item:

  Name of the stimulus item at that embedding location.

- path:

  path to stimulus file

## Source

Colon et al., in preparation.

## Details

The letters in the stimulus identifier indicate features of the
corresponding icon as follows: face/place, day/night,
female/male/church/house, old/young, black/white/big/small.
