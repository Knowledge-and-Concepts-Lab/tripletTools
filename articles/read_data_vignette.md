# Reading Triplet Data

``` r

library(tripletTools)
```

This package contains a set of functions to aid analysis of data from
*triadic comparisons* or *triplet* tasks. See the *tripletTools
Overview* vignette for demonstrations of the various tools.

This vignette describes how to get triplet data into R in a format that
works with the package. There are three common starting points:

1.  **Raw jsPsych exports** — you just finished data collection and have
    one CSV per participant straight out of jsPsych. Use
    [`read_raw_data()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/read_raw_data.md).
2.  **A legacy dataset** — you have a single CSV from an older
    experiment or a different collection platform, with column names
    that may not match the package’s conventions. Use
    [`read_legacy()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/read_legacy.md).
3.  **Already-processed data** — your data are already in the standard
    format (e.g. previously exported by one of the functions above).
    Jump straight to [Data file structure and naming
    conventions](#data-file-structure-and-naming-conventions) below to
    see how to load it.

------------------------------------------------------------------------

## Reading raw jsPsych data with `read_raw_data()`

If you collected your data with a jsPsych triplet experiment,
[`read_raw_data()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/read_raw_data.md)
handles the full cleaning pipeline in one call. Point it at the
directory containing the raw participant CSV files and it will:

1.  Read and combine all CSVs in the directory.
2.  Filter rows to experiment trials (`trial_category` equal to
    `"random"`, `"check"`, or `"validation"`).
3.  Apply quality-control exclusions: remove participants with too few
    trials (`filter_incomplete`), unusually fast mean reaction times
    (`filter_fast_responders`), or too many failed catch trials
    (`filter_failed_catch`).
4.  Strip file paths and extensions from stimulus names.
5.  Split the comma-separated `choices` column into labelled `Left` /
    `Right` columns and derive `winner` / `loser`.
6.  Assign a random 80/20 train/test split (configurable) via
    `assign_sample_sets`.
7.  Optionally write a cleaned trial CSV and a stimulus-level
    integer-mapping CSV to disk.

``` r

result <- read_raw_data(
  data_dir       = "experiment/raw_data/",   # folder of per-participant CSVs
  output_df      = "data/triplets_clean.csv",
  output_levels  = "data/stimulus_levels.csv",
  min_trials     = 200,       # drop participants with fewer trials than this
  min_mean_rt_ms = 200,       # drop participants with mean RT below this (ms)
  max_prop_wrong = 0.20,      # drop participants who fail >20% of catch trials
  test_prop      = 0.20,      # fraction of trials assigned to the test set
  seed           = 42
)
```

The function returns a list invisibly with two elements:

- `result$trials` — a data frame of cleaned trial-level data in the
  standard format (see [Data file
  structure](#data-file-structure-and-naming-conventions) below), ready
  to pass to
  [`get.combined()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md)
  or the embedding functions.
- `result$levels` — a data frame mapping each stimulus label to its
  integer index and file path.

All QC thresholds default to permissive values (`min_trials = 0`,
`min_mean_rt_ms = 0`, `max_prop_wrong = 1`), so calling
[`read_raw_data()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/read_raw_data.md)
with only `data_dir` set will read and clean the files without excluding
anyone.

------------------------------------------------------------------------

## Reading legacy data with `read_legacy()`

If your data come from an older experiment or a different collection
platform, the column names may not match the package’s conventions.
[`read_legacy()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/read_legacy.md)
handles a wide range of input formats by matching column names
case-insensitively and ignoring punctuation, so it can usually find the
right columns even when they are named differently.

Pass the path to a single combined CSV file:

``` r

result <- read_legacy("data/old_experiment.csv")
```

The function recognises many common alternative column names
automatically. For example:

| Standard name | Also recognised as |
|----|----|
| `worker_id` (participant) | `sessionID`, `puid`, `Participant.ID`, `sub_id`, `pid` |
| `Center` (target item) | `Target` |
| `Left` / `Right` (options) | `Option1` / `Option2` |
| `sampleAlg` | `AlgSample` |
| `sampleSet` | `Alg.Label`, `TrnTest` |

When a column cannot be found, it is derived where possible: `winner`
and `loser` are inferred from `Answer`, `Left`, and `Right`; if no
participant identifier is found, participants are assigned sequential
IDs (`"P1"`, `"P2"`, …); if no `sampleSet` column exists, 10% of trials
are randomly assigned to `"test"` and the rest to `"train"`.

[`read_legacy()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/read_legacy.md)
always writes two output files alongside the input:

- `<basename>_v2025.csv` — standardised trial data in the package’s
  column format.
- `<basename>_2025_levels.csv` — stimulus-level integer mapping.

The function returns a list invisibly with the paths to these two files:

``` r

result$data_file    # path to the standardised CSV
result$levels_file  # path to the levels mapping CSV
```

Once you have a standardised CSV from either function, load it into R
with
[`get.combined()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md)
as described in the next section.

------------------------------------------------------------------------

## Data file structure and naming conventions

The functions make use of two kinds of data files: *triplet data files*,
which contain information about each trial of a tradic comparison task,
and *embedding files*, which contain the coordinates of each item in an
embedding computed from triplet judgment data.

### Triplet data files

Triplet data files are `.csv` files generated by the software used to
collect triplet judgment data. The first row should be a header
specifying column names. Each subsequent row then records key
information for each trial of a triplet experiment. Typically data from
all participants in a given study are included in a single triplet data
file.

The triplet data file must be a `.csv` file and must contain columns
with the following names:

- *worker_id*: Arbitrary identifier for each participant
- *rt*: Response time for the trial
- *Center*, *Left*, *Right*: Strings indicating the items appearing in
  the center (target item), left side (option 1) and right side (option
  2).
- *Answer*: String indicating which option the participant chose.
- *sampleAlg*: ALgorithm used to sample the item: either random,
  validation, or check.
- *sampleSet*: Indicates whether the triplet was used to fit the
  embedding (train) or not (test).

The data file can also contain any other fields. Often data will include
an integer encoing of the triplet information with the following column
names:

- *head*, *winner*, *loser*: Integer indices for each item appearing in
  the triplet

Data in this format can be read into the current session using the
function `get_combined(fname)` where `fname` is the path to the data
file. This function returns a named list, where each element includes
the triplet judgment data from a single subject, and elements are named
by the subject identified. This package includes an example dataset in
this format, `icon_triplets`:

``` r

head(icon_triplets[[1]])
#>   head winner loser worker_id   rt Center  Left Right Answer  sampleAlg
#> 1   29     24    19  3n7ggxph 3096  pnhns pncnb pdcos  pncnb     random
#> 2   14      0    24  3n7ggxph 1100  fnmyb fdfob pncnb  fdfob     random
#> 3   30     19    24  3n7ggxph 2616  pnhob pncnb pdcos  pdcos     random
#> 4   17     12    13  3n7ggxph 2629  pdcns fnmow fnmob  fnmob validation
#> 5   29      9     8  3n7ggxph 2011  pnhns fnfow fnfob  fnfow     random
#> 6   25     23    12  3n7ggxph 1498  pncns fnmob pdhos  pdhos     random
#>   sampleSet
#> 1     train
#> 2     train
#> 3     train
#> 4     train
#> 5     train
#> 6     train
```

Here you can see the triplet judgment data for each trial for the first
participant in the experiment. Participants viewed the trials in the
same order they are listed in the matrix.

The data from each participant is a separate element in the list, and
the elements are labeled by the `worker\_id` label in the raw data file.
You can see all the subject labels as follows:

``` r

names(icon_triplets)
#> [1] "3n7ggxph" "b5wma4no" "d8mmm1qn" "jn7bbjc0" "pbby694o" "sc2xbd6w"
```

To learn more about this dataset, try
[`help(icon_triplets)`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/icon_triplets.md).

### Embedding data

Embedding data are `.csv` files containing embedding coordinates for
each stimulus item in the study. Depending on the study, there may be a
single *group embedding* computed from a group of participants, or
*individual embeddings* computed separately for each participant, or
both.

In both cases the `.csv` file must contain columns with the following
labels:

- *item*: A string indicating the label for the item.
- *dim_0 - dim_k*: One column for each dimension of the embedding,
  numbered beginning with zero, containing a numeric value that
  indicates the item’s location on the corresponding dimension of the
  embedding.

If a separate embedding was computed for each participant, then all
embeddings should appear within the same `.csv` file, and this should
also include the following column:

- *worker_id*: The random participant identifier, which should be the
  same as the identifier used in the triplet dataset.

To read in a group-based single embedding file you can just use standard
R:

    grpemb <- read.csv("filename.csv", row.names = "item", header = T)

For studies with separate embeddings computed for each participant, use
the `get.combined` function to read the data, setting the `eflag` flag
to `TRUE` to indicate these are embeddings:

    indemb <- get.combined("filename.csv", eflag = TRUE)

As with triplet data, this will create a named list where each element
contains the embedding information computed for one participant. The
elements are labeled by the participant id (`worker_id`). The
`icon_emb_ind` object contains a list of the kind returned by this
function:

``` r

head(icon_emb_ind[[1]])
#>           dim_0     dim_1      dim_2
#> fdfob 0.6411938 0.9710717 -0.9336048
#> fdfow 0.5504593 0.9558654 -0.9130039
#> fdfyb 0.2907846 0.6866032 -0.6360701
#> fdfyw 0.5820549 0.9266087 -0.8992642
#> fdmob 0.5776460 1.0081034 -0.8230091
#> fdmow 0.7911357 0.4666237 -0.4759873
```

The row names indicate the stimulus identity and the entries indicate
the coordinates of the stimulus along the first (dim_0), second (dim_1),
and third (dim_2) dimensions of the embedding.
