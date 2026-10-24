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
        # by_worker must hold full row dicts (with dim_* columns), not bare
        # item-name strings -- prep_person_files() needs r["item"]/r["dim_0"]
        # on each entry. A real deployment hit "'str' object has no
        # attribute 'keys'" here when this returned names instead of rows.
        for row in by_worker["p1"]:
            self.assertIsInstance(row, dict)
            self.assertIn("dim_0", row)

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


class TestBuildCanonicalItemsIntoPrepPersonFiles(unittest.TestCase):
    """End-to-end: raw CSV-shaped embedding rows -> build_canonical_items()
    -> prep_person_files(), the exact handoff that broke in a real
    deployment (build_canonical_items was storing bare item-name strings
    instead of full rows, so prep_person_files's r["item"]/r["dim_0"]
    lookups blew up on a plain str). Every other test exercises these two
    functions separately with hand-built inputs already in the shape each
    one expects, which is exactly why this gap wasn't caught before."""

    def test_full_pipeline_from_raw_rows(self):
        with tempfile.TemporaryDirectory() as tmp:
            embedding_rows = [
                {"worker_id": "p1", "item": "itemA", "dim_0": "1.0", "dim_1": "2.0"},
                {"worker_id": "p1", "item": "itemB", "dim_0": "3.0", "dim_1": "4.0"},
                {"worker_id": "p2", "item": "itemB", "dim_0": "5.0", "dim_1": "6.0"},
                {"worker_id": "p2", "item": "itemA", "dim_0": "7.0", "dim_1": "8.0"},
            ]
            worker_ids = ["p1", "p2"]
            item_order, embedding_rows_by_worker = jm.build_canonical_items(embedding_rows, worker_ids)
            item_index = {it: i for i, it in enumerate(item_order)}
            triplet_rows_by_worker = {"p1": [], "p2": []}

            setup_dir, orig_dir, mats_dir, trials_dir = jm.prep_person_files(
                Path(tmp), worker_ids, item_index, triplet_rows_by_worker,
                embedding_rows_by_worker, item_order
            )
            with open(orig_dir / "person0.csv", newline="") as f:
                rows = list(csv.DictReader(f))
            self.assertEqual(len(rows), 2)
            self.assertEqual(set(rows[0].keys()), {"item", "dim_0", "dim_1"})


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
    """Verifies the update step's Condor submit file/arguments are built
    correctly and its output is parsed correctly, without a real cluster --
    condor_submit/condor_wait are mocked (via subprocess.run, same as
    submit_and_wait's own two calls), and the mocked condor_submit writes
    the output files a real job would have produced, simulating completion."""

    def _patch_run(self, tmp, iter_dir, *, positions_text, beta_text, submit_returncode=0,
                    wait_returncode=0):
        def fake_run(cmd, **kwargs):
            if cmd[0] == "condor_submit":
                submit_path = Path(cmd[1])
                self.assertTrue(submit_path.exists())
                content = submit_path.read_text()
                self.assertIn("universe        = container", content)
                self.assertIn("condor_joint_manifold_update.R", content)
                # aligned/ is a newly-created SUBdirectory inside the job's
                # sandbox -- HTCondor's default output transfer doesn't
                # reliably recurse into those without naming them
                # explicitly (confirmed on a real deployment: positions.csv
                # and beta.csv, plain files, came back; aligned/ never did).
                self.assertIn("transfer_output_files   = positions.csv, beta.csv, aligned", content)
                if submit_returncode == 0:
                    (iter_dir / "positions.csv").write_text(positions_text)
                    (iter_dir / "beta.csv").write_text(beta_text)
                return mock.Mock(returncode=submit_returncode, stdout="1 job(s) submitted", stderr="")
            if cmd[0] == "condor_wait":
                return mock.Mock(returncode=wait_returncode)
            raise AssertionError(f"unexpected subprocess call: {cmd}")
        return mock.patch("condor_joint_manifold_workflow.subprocess.run", side_effect=fake_run)

    def test_builds_submit_file_and_parses_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            iter_dir = Path(tmp) / "iter1"
            iter_dir.mkdir()
            emb_dir = Path(tmp) / "embeddings"; emb_dir.mkdir()
            trials_dir = Path(tmp) / "person_trials"; trials_dir.mkdir()

            with self._patch_run(tmp, iter_dir, positions_text="position\n-0.5\n0.5\n",
                                  beta_text="beta0,beta1,bandwidth\n0.1,0.2,0.3\n"):
                positions, beta0, beta1, aligned_dir = jm.run_update_step(
                    iter_dir, 2, emb_dir, trials_dir, None, 0.0, 0.0,
                    resources={}, container_image="docker://example/image:latest"
                )
            self.assertEqual(positions, [-0.5, 0.5])
            self.assertAlmostEqual(beta0, 0.1)
            self.assertAlmostEqual(beta1, 0.2)

    def test_rejects_embeddings_dir_with_wrong_basename(self):
        with tempfile.TemporaryDirectory() as tmp:
            iter_dir = Path(tmp) / "iter1"; iter_dir.mkdir()
            bad_dir = Path(tmp) / "wrong_name"; bad_dir.mkdir()
            trials_dir = Path(tmp) / "person_trials"; trials_dir.mkdir()
            with self.assertRaises(AssertionError):
                jm.run_update_step(iter_dir, 2, bad_dir, trials_dir, None, 0.0, 0.0,
                                    resources={}, container_image="docker://example/image:latest")

    def test_old_positions_staged_under_distinct_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            prev_iter_dir = Path(tmp) / "iter1"; prev_iter_dir.mkdir()
            old_positions_path = prev_iter_dir / "positions.csv"
            old_positions_path.write_text("position\n0.1\n0.2\n")

            iter_dir = Path(tmp) / "iter2"; iter_dir.mkdir()
            emb_dir = Path(tmp) / "embeddings"; emb_dir.mkdir()
            trials_dir = Path(tmp) / "person_trials"; trials_dir.mkdir()

            seen_submit_files = []

            def fake_run(cmd, **kwargs):
                if cmd[0] == "condor_submit":
                    seen_submit_files.append(Path(cmd[1]).read_text())
                    (iter_dir / "positions.csv").write_text("position\n0.3\n0.4\n")
                    (iter_dir / "beta.csv").write_text("beta0,beta1,bandwidth\n0,0,1\n")
                    return mock.Mock(returncode=0, stdout="", stderr="")
                return mock.Mock(returncode=0)

            with mock.patch("condor_joint_manifold_workflow.subprocess.run", side_effect=fake_run):
                jm.run_update_step(iter_dir, 2, emb_dir, trials_dir, old_positions_path, 0.0, 0.0,
                                    resources={}, container_image="docker://example/image:latest")

            self.assertTrue((iter_dir / "old_positions_input.csv").exists())
            content = seen_submit_files[0]
            self.assertIn("old_positions_input.csv", content)
            self.assertIn("--old_positions=old_positions_input.csv", content)

    def test_missing_output_after_job_exits(self):
        with tempfile.TemporaryDirectory() as tmp:
            iter_dir = Path(tmp) / "iter1"; iter_dir.mkdir()
            emb_dir = Path(tmp) / "embeddings"; emb_dir.mkdir()
            trials_dir = Path(tmp) / "person_trials"; trials_dir.mkdir()

            def fake_run(cmd, **kwargs):
                if cmd[0] == "condor_submit":
                    return mock.Mock(returncode=0, stdout="", stderr="")  # no output files written
                return mock.Mock(returncode=0)

            with mock.patch("condor_joint_manifold_workflow.subprocess.run", side_effect=fake_run):
                with self.assertRaises(SystemExit):
                    jm.run_update_step(iter_dir, 2, emb_dir, trials_dir, None, 0.0, 0.0,
                                        resources={}, container_image="docker://example/image:latest")


if __name__ == "__main__":
    unittest.main()
