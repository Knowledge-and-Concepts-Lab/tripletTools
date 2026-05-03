# Clean raw jsPsych triplet experiment data

Reads all CSV files exported from a jsPsych triplet experiment, filters
to experiment trials, applies quality-control exclusions, and returns
cleaned data ready for modelling. Optionally writes the results to disk.

## Usage

``` r
read_raw_data(
  data_dir = ".",
  output_df = NULL,
  output_levels = NULL,
  min_trials = 0,
  min_mean_rt_ms = 0,
  max_prop_wrong = 1,
  test_prop = 0.1,
  seed = 42,
  stimuli_extension = ".png"
)
```

## Arguments

- data_dir:

  Character. Path to the directory containing raw CSV exports. Default:
  `"experiment/raw_data/"`.

- output_df:

  Character or `NULL`. File path for the cleaned trial-level CSV. Set to
  `NULL` to skip writing. Default: `"icon_fp_clean.csv"` (written to the
  working directory).

- output_levels:

  Character or `NULL`. File path for the stimulus-level mapping CSV. Set
  to `NULL` to skip writing. Default: `"icon_fp_levels.csv"` (written to
  the working directory).

- min_trials:

  Integer. Minimum number of experiment trials a participant must have
  completed to be retained. Passed to
  [`filter_incomplete`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/filter_incomplete.md).
  Default: `200`.

- min_mean_rt_ms:

  Numeric. Minimum mean reaction time in milliseconds for a participant
  to be retained. Passed to
  [`filter_fast_responders`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/filter_fast_responders.md).
  Default: `200`.

- max_prop_wrong:

  Numeric between 0 and 1. Maximum proportion of failed catch trials
  before a participant is excluded. Passed to
  [`filter_failed_catch`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/filter_failed_catch.md).
  Default: `0.2`.

- test_prop:

  Numeric between 0 and 1. Proportion of non-check trials assigned to
  the test set in the train/test split. Passed to
  [`assign_sample_sets`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/assign_sample_sets.md).
  Default: `0.2`.

- seed:

  Integer. Random seed for reproducible train/test splitting. Passed to
  [`assign_sample_sets`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/assign_sample_sets.md).
  Default: `42`.

- stimuli_extension:

  Character. File extension (including the leading dot) to strip from
  stimulus and choice names. Default: `".png"`.

## Value

A list returned invisibly with two elements:

- `trials`:

  Data frame of cleaned trial-level data with columns `head`, `winner`,
  `loser`, `worker_id`, `rt`, `Center`, `Left`, `Right`, `Answer`,
  `sampleAlg`, and `sampleSet`.

- `levels`:

  Data frame mapping integer stimulus indices to file names and paths.
