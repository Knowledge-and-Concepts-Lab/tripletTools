"""Unit tests for condor_group_diff_workflow.py's pure logic (replicate
construction, permutation p-value, CSV filtering) -- everything that
doesn't require a real HTCondor cluster or condor_submit/condor_wait.

Run locally with:
    python3 -m unittest inst/condor/test_condor_group_diff_workflow.py -v

Plain unittest (stdlib only, no extra dependency beyond PyYAML). Not
invoked by devtools::test()/R CMD check -- a developer-facing check for
the Python side of this Condor workflow.
"""
import csv
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import condor_group_diff_workflow as gd  # noqa: E402


class TestBuildReplicates(unittest.TestCase):
    def test_true_split_is_replicate_zero(self):
        worker_ids = ["p1", "p2", "p3", "p4", "p5", "p6"]
        true_groups = {"p1": "A", "p2": "A", "p3": "A",
                        "p4": "B", "p5": "B", "p6": "B"}
        reps = gd.build_replicates(worker_ids, true_groups, n1=3, n2=3,
                                    n_permutations=5, seed=1)
        self.assertEqual(reps[0]["replicate_id"], 0)
        self.assertTrue(reps[0]["is_true"])
        self.assertEqual(sorted(reps[0]["side_a"]), ["p1", "p2", "p3"])
        self.assertEqual(sorted(reps[0]["side_b"]), ["p4", "p5", "p6"])

    def test_null_replicates_preserve_true_group_sizes(self):
        worker_ids = [f"p{i}" for i in range(1, 11)]  # 10 participants
        true_groups = {w: ("A" if i < 3 else "B") for i, w in enumerate(worker_ids)}
        # true sizes: n1=3, n2=7 -- deliberately unequal
        reps = gd.build_replicates(worker_ids, true_groups, n1=3, n2=7,
                                    n_permutations=20, seed=1)
        for rep in reps[1:]:
            self.assertEqual(len(rep["side_a"]), 3)
            self.assertEqual(len(rep["side_b"]), 7)
            # every participant assigned to exactly one side, no duplicates
            self.assertEqual(sorted(rep["side_a"] + rep["side_b"]), sorted(worker_ids))
            self.assertFalse(rep["is_true"])

    def test_null_replicates_are_reproducible_given_seed(self):
        worker_ids = [f"p{i}" for i in range(1, 11)]
        true_groups = {w: ("A" if i < 5 else "B") for i, w in enumerate(worker_ids)}
        reps1 = gd.build_replicates(worker_ids, true_groups, n1=5, n2=5,
                                     n_permutations=3, seed=42)
        reps2 = gd.build_replicates(worker_ids, true_groups, n1=5, n2=5,
                                     n_permutations=3, seed=42)
        self.assertEqual(reps1, reps2)

    def test_different_replicates_differ(self):
        worker_ids = [f"p{i}" for i in range(1, 21)]
        true_groups = {w: ("A" if i < 10 else "B") for i, w in enumerate(worker_ids)}
        reps = gd.build_replicates(worker_ids, true_groups, n1=10, n2=10,
                                    n_permutations=5, seed=1)
        side_a_sets = [tuple(sorted(r["side_a"])) for r in reps[1:]]
        # Not a strict guarantee for tiny n, but with 20 participants and
        # 5 draws, getting the identical partition twice by chance is
        # astronomically unlikely -- a real bug (e.g. reusing one seed for
        # every replicate) would make every entry identical.
        self.assertGreater(len(set(side_a_sets)), 1)


class TestPermutationPValue(unittest.TestCase):
    def test_observed_below_all_nulls_gives_smallest_possible_p(self):
        p = gd.permutation_p_value(0.1, [0.5, 0.6, 0.7, 0.8])
        self.assertAlmostEqual(p, 1 / 5)

    def test_observed_above_all_nulls_gives_largest_possible_p(self):
        p = gd.permutation_p_value(0.9, [0.1, 0.2, 0.3, 0.4])
        self.assertAlmostEqual(p, 5 / 5)

    def test_observed_equal_to_a_null_value_counts_as_extreme(self):
        p = gd.permutation_p_value(0.5, [0.5, 0.6, 0.7])
        self.assertAlmostEqual(p, 2 / 4)


class TestCsvHelpers(unittest.TestCase):
    def test_read_triplet_rows_requires_worker_id_column(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "bad.csv"
            path.write_text("Center,Left,Right,Answer\nx,y,z,y\n")
            with self.assertRaises(SystemExit):
                gd.read_triplet_rows(path)

    def test_read_triplet_rows_requires_hard_columns(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "bad.csv"
            path.write_text("worker_id,Center,Left\np1,a,b\n")  # missing Right, Answer
            with self.assertRaises(SystemExit):
                gd.read_triplet_rows(path)

    def test_read_triplet_rows_trims_to_needed_columns(self):
        # A realistic export carries extra columns (head, winner, loser, rt,
        # sampleAlg, ...) that run_group_embedding_from_list() never reads --
        # every one of them gets rewritten into every (replicate, side)
        # output file otherwise, so trimming here matters for real-world
        # performance, not just tidiness.
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "full.csv"
            path.write_text(
                "head,winner,loser,worker_id,rt,Center,Left,Right,Answer,sampleAlg,sampleSet\n"
                "1,2,3,p1,1000,a,b,c,b,random,train\n"
            )
            fieldnames, rows = gd.read_triplet_rows(path)
            self.assertEqual(
                set(fieldnames),
                {"worker_id", "Center", "Left", "Right", "Answer", "sampleSet"},
            )
            self.assertNotIn("head", rows[0])
            self.assertNotIn("rt", rows[0])

    def test_read_triplet_rows_tolerates_missing_sampleset(self):
        # sampleSet is soft-required: run_group_embedding_from_list() falls
        # back to a random 70/30 split if it's absent, so this should warn
        # (via a printed note) rather than exit.
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "no_sampleset.csv"
            path.write_text("worker_id,Center,Left,Right,Answer\np1,a,b,c,b\n")
            fieldnames, rows = gd.read_triplet_rows(path)  # must not raise
            self.assertNotIn("sampleSet", fieldnames)

    def test_group_rows_by_worker(self):
        rows = [
            {"worker_id": "p1", "Answer": "b"},
            {"worker_id": "p2", "Answer": "c"},
            {"worker_id": "p1", "Answer": "a"},
        ]
        grouped = gd.group_rows_by_worker(rows)
        self.assertEqual(len(grouped["p1"]), 2)
        self.assertEqual(len(grouped["p2"]), 1)
        self.assertNotIn("p3", grouped)

    def test_write_filtered_csv_keeps_only_requested_workers(self):
        fieldnames = ["worker_id", "Center", "Left", "Right", "Answer"]
        rows = [
            {"worker_id": "p1", "Center": "a", "Left": "b", "Right": "c", "Answer": "b"},
            {"worker_id": "p2", "Center": "a", "Left": "b", "Right": "c", "Answer": "c"},
            {"worker_id": "p3", "Center": "a", "Left": "b", "Right": "c", "Answer": "b"},
        ]
        rows_by_worker = gd.group_rows_by_worker(rows)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "filtered.csv"
            gd.write_filtered_csv(path, fieldnames, rows_by_worker, ["p1", "p3"])
            with open(path, newline="") as f:
                out_rows = list(csv.DictReader(f))
            self.assertEqual([r["worker_id"] for r in out_rows], ["p1", "p3"])

    def test_write_filtered_csv_preserves_requested_worker_order(self):
        # Order matters for reproducibility of the written CSV, even though
        # it doesn't affect the embedding fit itself.
        fieldnames = ["worker_id", "Answer"]
        rows = [
            {"worker_id": "p1", "Answer": "x"},
            {"worker_id": "p2", "Answer": "y"},
        ]
        rows_by_worker = gd.group_rows_by_worker(rows)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "filtered.csv"
            gd.write_filtered_csv(path, fieldnames, rows_by_worker, ["p2", "p1"])
            with open(path, newline="") as f:
                out_rows = list(csv.DictReader(f))
            self.assertEqual([r["worker_id"] for r in out_rows], ["p2", "p1"])

    def test_read_group_labels(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "groups.csv"
            path.write_text("worker_id,group\np1,A\np2,A\np3,B\n")
            labels = gd.read_group_labels(path)
            self.assertEqual(labels, {"p1": "A", "p2": "A", "p3": "B"})


if __name__ == "__main__":
    unittest.main()
