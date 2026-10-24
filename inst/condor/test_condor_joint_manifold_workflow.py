"""Unit tests for condor_joint_manifold_workflow.py's pure logic (CSV
reading/validation, canonical item ordering, per-person file prep, the
shared submit_jobs_with_retry() helper) -- everything that doesn't require
a real HTCondor cluster, condor_submit/condor_wait, or an R installation.

Run locally with:
    python3 -m unittest inst/condor/test_condor_joint_manifold_workflow.py -v

Plain unittest (stdlib only, no extra dependency beyond PyYAML). Not
invoked by devtools::test()/R CMD check -- a developer-facing check for
the Python side of this Condor workflow.
"""
import csv
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import condor_joint_manifold_workflow as jm  # noqa: E402


def write_csv_text(path, text):
    path.write_text(text)


class TestReadCombinedTriplets(unittest.TestCase):
    def test_requires_core_columns(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "bad.csv"
            write_csv_text(path, "worker_id,Center,Left\np1,a,b\n")
            with self.assertRaises(SystemExit):
                jm.read_combined_triplets(path)

    def test_reads_valid_rows(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "ok.csv"
            write_csv_text(
                path,
                "worker_id,Center,Left,Right,Answer,sampleAlg,sampleSet\n"
                "p1,a,b,c,b,random,train\n",
            )
            rows = jm.read_combined_triplets(path)
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["worker_id"], "p1")


class TestReadCombinedEmbeddings(unittest.TestCase):
    def test_requires_worker_id_and_item(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "bad.csv"
            write_csv_text(path, "worker_id,dim_0\np1,1.0\n")
            with self.assertRaises(SystemExit):
                jm.read_combined_embeddings(path)

    def test_reads_dim_columns(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "ok.csv"
            write_csv_text(path, "worker_id,item,dim_0,dim_1\np1,itemA,1.0,2.0\n")
            rows, dim_cols = jm.read_combined_embeddings(path)
            self.assertEqual(dim_cols, ["dim_0", "dim_1"])
            self.assertEqual(rows[0]["item"], "itemA")


class TestBuildCanonicalItems(unittest.TestCase):
    def test_consistent_item_sets_pass(self):
        rows = [
            {"worker_id": "p1", "item": "a", "dim_0": "1"},
            {"worker_id": "p1", "item": "b", "dim_0": "2"},
            {"worker_id": "p2", "item": "b", "dim_0": "3"},
            {"worker_id": "p2", "item": "a", "dim_0": "4"},
        ]
        item_order, by_worker = jm.build_canonical_items(rows, ["p1", "p2"])
        self.assertEqual(set(item_order), {"a", "b"})
        self.assertEqual(len(by_worker["p1"]), 2)

    def test_mismatched_item_set_exits(self):
        rows = [
            {"worker_id": "p1", "item": "a", "dim_0": "1"},
            {"worker_id": "p1", "item": "b", "dim_0": "2"},
            {"worker_id": "p2", "item": "a", "dim_0": "3"},  # missing "b"
        ]
        with self.assertRaises(SystemExit):
            jm.build_canonical_items(rows, ["p1", "p2"])


class TestWinnerLoserItem(unittest.TestCase):
    def test_answer_matches_left(self):
        row = {"Left": "b", "Right": "c", "Answer": "b"}
        winner, loser = jm.winner_loser_item(row)
        self.assertEqual((winner, loser), ("b", "c"))

    def test_answer_matches_right(self):
        row = {"Left": "b", "Right": "c", "Answer": "c"}
        winner, loser = jm.winner_loser_item(row)
        self.assertEqual((winner, loser), ("c", "b"))


class TestPrepPersonFiles(unittest.TestCase):
    def _setup(self, tmp):
        items = ["itemA", "itemB", "itemC"]
        item_index = {it: i for i, it in enumerate(items)}
        worker_ids = ["p1", "p2"]
        embedding_rows_by_worker = {
            "p1": [{"worker_id": "p1", "item": it, "dim_0": str(i), "dim_1": str(i * 2)}
                   for i, it in enumerate(items)],
            "p2": [{"worker_id": "p2", "item": it, "dim_0": str(i + 10), "dim_1": str(i * 2 + 10)}
                   for i, it in enumerate(items)],
        }
        triplet_rows_by_worker = {
            "p1": [
                {"worker_id": "p1", "Center": "itemA", "Left": "itemB", "Right": "itemC",
                 "Answer": "itemB", "sampleAlg": "random", "sampleSet": "train"},
                {"worker_id": "p1", "Center": "itemA", "Left": "itemC", "Right": "itemB",
                 "Answer": "itemC", "sampleAlg": "random", "sampleSet": "test"},
                {"worker_id": "p1", "Center": "itemA", "Left": "itemB", "Right": "itemC",
                 "Answer": "itemB", "sampleAlg": "validation", "sampleSet": None},
                {"worker_id": "p1", "Center": "itemA", "Left": "itemB", "Right": "itemC",
                 "Answer": "itemC", "sampleAlg": "check", "sampleSet": None},
            ],
            "p2": [
                {"worker_id": "p2", "Center": "itemB", "Left": "itemA", "Right": "itemC",
                 "Answer": "itemA", "sampleAlg": "random", "sampleSet": "train"},
            ],
        }
        work_dir = Path(tmp)
        return work_dir, worker_ids, item_index, triplet_rows_by_worker, embedding_rows_by_worker, items

    def test_creates_expected_directories_and_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            args = self._setup(tmp)
            work_dir = args[0]
            setup_dir, orig_dir, mats_dir, trials_dir = jm.prep_person_files(*args)

            self.assertTrue((orig_dir / "person0.csv").exists())
            self.assertTrue((orig_dir / "person1.csv").exists())
            self.assertTrue((mats_dir / "person0_train.csv").exists())
            self.assertTrue((mats_dir / "person0_test.csv").exists())
            self.assertTrue((trials_dir / "person0.csv").exists())

    def test_original_embedding_reindexed_to_canonical_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            args = self._setup(tmp)
            _, orig_dir, _, _ = jm.prep_person_files(*args)
            with open(orig_dir / "person0.csv", newline="") as f:
                rows = list(csv.DictReader(f))
            self.assertEqual([r["item"] for r in rows], ["itemA", "itemB", "itemC"])
            self.assertEqual(rows[0]["dim_0"], "0")  # itemA was dim_0=0 for p1

    def test_random_trials_only_excludes_validation_and_check(self):
        with tempfile.TemporaryDirectory() as tmp:
            args = self._setup(tmp)
            _, _, _, trials_dir = jm.prep_person_files(*args)
            with open(trials_dir / "person0.csv", newline="") as f:
                rows = list(csv.DictReader(f))
            self.assertEqual(len(rows), 2)  # only the 2 "random" rows for p1

    def test_train_test_split_follows_sampleset(self):
        with tempfile.TemporaryDirectory() as tmp:
            args = self._setup(tmp)
            _, _, mats_dir, _ = jm.prep_person_files(*args)
            with open(mats_dir / "person0_train.csv", newline="") as f:
                train_rows = list(csv.DictReader(f))
            with open(mats_dir / "person0_test.csv", newline="") as f:
                test_rows = list(csv.DictReader(f))
            self.assertEqual(len(train_rows), 1)
            self.assertEqual(len(test_rows), 1)

    def test_item_indices_are_zero_based_and_correct(self):
        with tempfile.TemporaryDirectory() as tmp:
            args = self._setup(tmp)
            _, _, mats_dir, _ = jm.prep_person_files(*args)
            with open(mats_dir / "person0_train.csv", newline="") as f:
                row = next(csv.DictReader(f))
            # Center=itemA(0), Answer/winner=itemB(1), loser=itemC(2)
            self.assertEqual(row["head"], "0")
            self.assertEqual(row["winner"], "1")
            self.assertEqual(row["loser"], "2")

    def test_person_with_no_random_trials_gets_empty_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            items = ["itemA", "itemB"]
            item_index = {it: i for i, it in enumerate(items)}
            embedding_rows_by_worker = {
                "p1": [{"worker_id": "p1", "item": it, "dim_0": "0"} for it in items],
            }
            triplet_rows_by_worker = {"p1": []}
            setup_dir, orig_dir, mats_dir, trials_dir = jm.prep_person_files(
                Path(tmp), ["p1"], item_index, triplet_rows_by_worker, embedding_rows_by_worker, items
            )
            with open(mats_dir / "person0_train.csv", newline="") as f:
                self.assertEqual(list(csv.DictReader(f)), [])


class TestSubmitJobsWithRetry(unittest.TestCase):
    def test_all_succeed_first_try(self):
        with tempfile.TemporaryDirectory() as tmp:
            stage_dir = Path(tmp)
            jobs = [("a", "out_a.csv"), ("b", "out_b.csv")]
            calls = []

            def build_and_submit(jobs_subset):
                calls.append(list(jobs_subset))
                for _, out in jobs_subset:
                    (stage_dir / out).write_text("data\n")

            jm.submit_jobs_with_retry(stage_dir, jobs, output_col=1,
                                       build_and_submit=build_and_submit, label="test")
            self.assertEqual(len(calls), 1)

    def test_missing_output_retried(self):
        with tempfile.TemporaryDirectory() as tmp:
            stage_dir = Path(tmp)
            jobs = [("a", "out_a.csv"), ("b", "out_b.csv")]
            calls = []

            def build_and_submit(jobs_subset):
                calls.append([j[0] for j in jobs_subset])
                for name, out in jobs_subset:
                    if name == "b" and len(calls) == 1:
                        (stage_dir / out).touch()
                    else:
                        (stage_dir / out).write_text("data\n")

            jm.submit_jobs_with_retry(stage_dir, jobs, output_col=1,
                                       build_and_submit=build_and_submit, label="test")
            self.assertEqual(calls, [["a", "b"], ["b"]])

    def test_extra_outputs_also_validated(self):
        with tempfile.TemporaryDirectory() as tmp:
            stage_dir = Path(tmp)
            jobs = [("a", "out_a.csv")]
            calls = []

            def build_and_submit(jobs_subset):
                calls.append(len(calls))
                (stage_dir / "out_a.csv").write_text("data\n")
                if len(calls) < 2:
                    return  # extra file never written on first attempt
                (stage_dir / "extra_a.csv").write_text("data\n")

            jm.submit_jobs_with_retry(
                stage_dir, jobs, output_col=1, build_and_submit=build_and_submit, label="test",
                extra_outputs=lambda j: [stage_dir / "extra_a.csv"],
            )
            self.assertEqual(len(calls), 2)

    def test_persistently_missing_exits(self):
        with tempfile.TemporaryDirectory() as tmp:
            stage_dir = Path(tmp)
            jobs = [("a", "out_a.csv")]
            with self.assertRaises(SystemExit):
                jm.submit_jobs_with_retry(stage_dir, jobs, output_col=1,
                                           build_and_submit=lambda s: None,
                                           label="test", max_retries=1)


class TestRunUpdateStep(unittest.TestCase):
    """Verifies the Rscript command is built correctly and output files are
    parsed correctly, without actually invoking Rscript."""

    def test_builds_command_and_parses_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            iter_dir = Path(tmp) / "iter1"
            iter_dir.mkdir()

            def fake_run(cmd, capture_output, text):
                # Simulate the R script's own output files.
                pos_arg = next(c for c in cmd if c.startswith("--output_positions="))
                beta_arg = next(c for c in cmd if c.startswith("--output_beta="))
                Path(pos_arg.split("=", 1)[1]).write_text("position\n-0.5\n0.5\n")
                Path(beta_arg.split("=", 1)[1]).write_text("beta0,beta1,bandwidth\n0.1,0.2,0.3\n")
                return mock.Mock(returncode=0, stdout="ok", stderr="")

            with mock.patch("condor_joint_manifold_workflow.subprocess.run", side_effect=fake_run):
                positions, beta0, beta1, aligned_dir = jm.run_update_step(
                    iter_dir, 2, Path(tmp) / "emb", Path(tmp) / "trials", None, 0.0, 0.0
                )
            self.assertEqual(positions, [-0.5, 0.5])
            self.assertAlmostEqual(beta0, 0.1)
            self.assertAlmostEqual(beta1, 0.2)

    def test_nonzero_exit_code_exits(self):
        with tempfile.TemporaryDirectory() as tmp:
            iter_dir = Path(tmp) / "iter1"
            iter_dir.mkdir()

            def fake_run(cmd, capture_output, text):
                return mock.Mock(returncode=1, stdout="", stderr="boom")

            with mock.patch("condor_joint_manifold_workflow.subprocess.run", side_effect=fake_run):
                with self.assertRaises(SystemExit):
                    jm.run_update_step(iter_dir, 2, Path(tmp) / "emb", Path(tmp) / "trials",
                                        None, 0.0, 0.0)


if __name__ == "__main__":
    unittest.main()
