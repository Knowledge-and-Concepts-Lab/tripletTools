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
  stimuli_extension = ".png",
  worker_id_regex = NULL
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

- worker_id_regex:

  Character or `NULL`. Only used when a file has no recognised
  participant-ID column (see *Column-name flexibility* below). A regular
  expression with one capture group, applied to the file's base name
  (without directory or extension); the captured group becomes that
  file's `worker_id`. For example, `"motion_(\\d+)_part\\d+"` extracts
  `"87059"` from `"motion_87059_part1.csv"`. If `NULL` (default), or if
  the regex does not match, the full base file name is used as the
  `worker_id` instead.

## Value

A list returned invisibly with two elements:

- `trials`:

  Data frame of cleaned trial-level data with columns `head`, `winner`,
  `loser`, `worker_id`, `rt`, `Center`, `Left`, `Right`, `Answer`,
  `sampleAlg`, and `sampleSet`.

- `levels`:

  Data frame mapping integer stimulus indices to file names and paths.

## Column-name flexibility

Different jsPsych triplet experiments (and different versions of the
same experiment code) do not always export identical column names.
Before combining files, each one is checked for a small set of known
aliases:

- Trial category:

  Recognised input names: `trial_category`, `sampleAlg`, `AlgSample`. If
  none is found in a file, the function stops with an error naming that
  file.

- Participant ID (`worker_id`):

  Recognised input names: `worker_id`, `sessionID`, `session_ID`,
  `puid`, `Participant.ID`, `sub_id`, `pid`. If none is found, an ID is
  derived from the file name instead (see `worker_id_regex`) rather than
  raising an error, since some jsPsych configurations never write a
  participant-ID column at all and rely on one file per participant
  instead.
