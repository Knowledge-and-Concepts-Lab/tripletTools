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
import math
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


class TestSubmitAndWait(unittest.TestCase):
    """A job that comes back HELD (e.g. a transient bad-execute-node Docker/
    CVMFS mount failure, seen live on a real CHTC deployment) must not make
    condor_wait block forever -- submit_and_wait() polls with condor_wait
    -wait, auto-releases anything it finds held via condor_q -held, and
    only gives up once a job has held repeatedly past HELD_JOB_MAX_RELEASES."""

    def test_succeeds_without_any_hold(self):
        calls = []

        def fake_run(cmd, **kwargs):
            calls.append(cmd[0])
            if cmd[0] == "condor_submit":
                return mock.Mock(returncode=0, stdout="1 job(s) submitted to cluster 42.",
                                  stderr="")
            if cmd[0] == "condor_wait":
                return mock.Mock(returncode=0)
            raise AssertionError(f"unexpected call: {cmd}")

        with mock.patch("condor_joint_manifold_workflow.subprocess.run", side_effect=fake_run):
            jm.submit_and_wait(Path("sub.sub"), Path("log"), "test job")
        self.assertNotIn("condor_q", calls)
        self.assertNotIn("condor_release", calls)

    def test_held_job_is_auto_released_then_succeeds(self):
        wait_calls = {"n": 0}

        def fake_run(cmd, **kwargs):
            if cmd[0] == "condor_submit":
                return mock.Mock(returncode=0, stdout="1 job(s) submitted to cluster 42.",
                                  stderr="")
            if cmd[0] == "condor_wait":
                wait_calls["n"] += 1
                # Held on the first poll, gone (released, then finished) by the second.
                return mock.Mock(returncode=0 if wait_calls["n"] > 1 else 1)
            if cmd[0] == "condor_q":
                if wait_calls["n"] == 1:
                    return mock.Mock(returncode=0, stdout="21 Error from slot1_11@e2472: "
                                                           "invalid mount config for /cvmfs\n")
                return mock.Mock(returncode=0, stdout="")
            if cmd[0] == "condor_release":
                self.assertEqual(cmd[1], "42.21")
                return mock.Mock(returncode=0)
            raise AssertionError(f"unexpected call: {cmd}")

        with mock.patch("condor_joint_manifold_workflow.subprocess.run", side_effect=fake_run):
            jm.submit_and_wait(Path("sub.sub"), Path("log"), "test job")
        self.assertEqual(wait_calls["n"], 2)

    def test_repeatedly_held_job_gives_up(self):
        def fake_run(cmd, **kwargs):
            if cmd[0] == "condor_submit":
                return mock.Mock(returncode=0, stdout="1 job(s) submitted to cluster 42.",
                                  stderr="")
            if cmd[0] == "condor_wait":
                return mock.Mock(returncode=1)
            if cmd[0] == "condor_q":
                return mock.Mock(returncode=0, stdout="21 same transient-looking reason every time\n")
            if cmd[0] == "condor_release":
                return mock.Mock(returncode=0)
            raise AssertionError(f"unexpected call: {cmd}")

        with mock.patch("condor_joint_manifold_workflow.subprocess.run", side_effect=fake_run):
            with self.assertRaises(SystemExit):
                jm.submit_and_wait(Path("sub.sub"), Path("log"), "test job")

    def test_unparseable_cluster_id_exits_on_timeout_without_querying_condor_q(self):
        def fake_run(cmd, **kwargs):
            if cmd[0] == "condor_submit":
                return mock.Mock(returncode=0, stdout="not the format we expected", stderr="")
            if cmd[0] == "condor_wait":
                return mock.Mock(returncode=1)
            raise AssertionError(f"unexpected call: {cmd}")

        with mock.patch("condor_joint_manifold_workflow.subprocess.run", side_effect=fake_run):
            with self.assertRaises(SystemExit):
                jm.submit_and_wait(Path("sub.sub"), Path("log"), "test job")


class TestRunUpdateStep(unittest.TestCase):
    """Verifies the update step's Condor submit file/arguments are built
    correctly and its output is parsed correctly, without a real cluster --
    condor_submit/condor_wait are mocked (via subprocess.run, same as
    submit_and_wait's own two calls), and the mocked condor_submit writes
    the output files a real job would have produced, simulating completion."""

    def _patch_run(self, tmp, iter_dir, *, positions_text, alpha_text, submit_returncode=0,
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
                # and alpha.csv, plain files, came back; aligned/ never did).
                self.assertIn("transfer_output_files   = positions.csv, alpha.csv, aligned", content)
                if submit_returncode == 0:
                    (iter_dir / "positions.csv").write_text(positions_text)
                    (iter_dir / "alpha.csv").write_text(alpha_text)
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
                                  alpha_text="alpha\n1.1\n1.2\n"):
                positions, alphas, aligned_dir = jm.run_update_step(
                    iter_dir, 2, emb_dir, trials_dir, None, None,
                    resources={}, container_image="docker://example/image:latest"
                )
            self.assertEqual(positions, [-0.5, 0.5])
            self.assertEqual(alphas, [1.1, 1.2])

    def test_rejects_embeddings_dir_with_wrong_basename(self):
        with tempfile.TemporaryDirectory() as tmp:
            iter_dir = Path(tmp) / "iter1"; iter_dir.mkdir()
            bad_dir = Path(tmp) / "wrong_name"; bad_dir.mkdir()
            trials_dir = Path(tmp) / "person_trials"; trials_dir.mkdir()
            with self.assertRaises(AssertionError):
                jm.run_update_step(iter_dir, 2, bad_dir, trials_dir, None, None,
                                    resources={}, container_image="docker://example/image:latest")

    def test_old_positions_and_alpha_staged_under_distinct_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            prev_iter_dir = Path(tmp) / "iter1"; prev_iter_dir.mkdir()
            old_positions_path = prev_iter_dir / "positions.csv"
            old_positions_path.write_text("position\n0.1\n0.2\n")
            old_alpha_path = prev_iter_dir / "alpha.csv"
            old_alpha_path.write_text("alpha\n1.0\n1.0\n")

            iter_dir = Path(tmp) / "iter2"; iter_dir.mkdir()
            emb_dir = Path(tmp) / "embeddings"; emb_dir.mkdir()
            trials_dir = Path(tmp) / "person_trials"; trials_dir.mkdir()

            seen_submit_files = []

            def fake_run(cmd, **kwargs):
                if cmd[0] == "condor_submit":
                    seen_submit_files.append(Path(cmd[1]).read_text())
                    (iter_dir / "positions.csv").write_text("position\n0.3\n0.4\n")
                    (iter_dir / "alpha.csv").write_text("alpha\n1.1\n1.1\n")
                    return mock.Mock(returncode=0, stdout="", stderr="")
                return mock.Mock(returncode=0)

            with mock.patch("condor_joint_manifold_workflow.subprocess.run", side_effect=fake_run):
                jm.run_update_step(iter_dir, 2, emb_dir, trials_dir, old_positions_path, old_alpha_path,
                                    resources={}, container_image="docker://example/image:latest")

            self.assertTrue((iter_dir / "old_positions_input.csv").exists())
            self.assertTrue((iter_dir / "old_alpha_input.csv").exists())
            content = seen_submit_files[0]
            self.assertIn("--old_positions=old_positions_input.csv", content)
            self.assertIn("--old_alpha=old_alpha_input.csv", content)

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
                    jm.run_update_step(iter_dir, 2, emb_dir, trials_dir, None, None,
                                        resources={}, container_image="docker://example/image:latest")


class TestIdListRoundTrip(unittest.TestCase):
    def test_write_then_read(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "ids.txt"
            jm.write_id_list(path, ["p1", "p2", "p3"])
            self.assertEqual(jm.read_id_list(path), ["p1", "p2", "p3"])


class TestCheckOrRecordIds(unittest.TestCase):
    def test_first_run_records(self):
        with tempfile.TemporaryDirectory() as tmp:
            setup_dir = Path(tmp)
            jm.check_or_record_ids(setup_dir, ["p1", "p2"], ["a", "b"])
            self.assertEqual(jm.read_id_list(setup_dir / "worker_ids.txt"), ["p1", "p2"])
            self.assertEqual(jm.read_id_list(setup_dir / "item_order.txt"), ["a", "b"])

    def test_matching_resume_passes_silently(self):
        with tempfile.TemporaryDirectory() as tmp:
            setup_dir = Path(tmp)
            jm.check_or_record_ids(setup_dir, ["p1", "p2"], ["a", "b"])
            jm.check_or_record_ids(setup_dir, ["p1", "p2"], ["a", "b"])  # must not raise

    def test_mismatched_worker_ids_exits(self):
        with tempfile.TemporaryDirectory() as tmp:
            setup_dir = Path(tmp)
            jm.check_or_record_ids(setup_dir, ["p1", "p2"], ["a", "b"])
            with self.assertRaises(SystemExit):
                jm.check_or_record_ids(setup_dir, ["p1", "p3"], ["a", "b"])

    def test_mismatched_item_order_exits(self):
        with tempfile.TemporaryDirectory() as tmp:
            setup_dir = Path(tmp)
            jm.check_or_record_ids(setup_dir, ["p1", "p2"], ["a", "b"])
            with self.assertRaises(SystemExit):
                jm.check_or_record_ids(setup_dir, ["p1", "p2"], ["b", "a"])


class TestIterationIsComplete(unittest.TestCase):
    def _make_complete_iter(self, iter_dir, n_people):
        emb_dir = iter_dir / "refit" / "embeddings"
        emb_dir.mkdir(parents=True)
        for i in range(n_people):
            (emb_dir / f"person{i}.csv").write_text("item,dim_0\na,1.0\n")
        (iter_dir / "positions.csv").write_text("position\n0.1\n0.2\n")
        (iter_dir / "alpha.csv").write_text("alpha\n1.0\n1.0\n")

    def test_complete_iteration_is_true(self):
        with tempfile.TemporaryDirectory() as tmp:
            iter_dir = Path(tmp) / "iter1"
            self._make_complete_iter(iter_dir, 2)
            self.assertTrue(jm.iteration_is_complete(iter_dir, 2))

    def test_missing_positions_is_false(self):
        with tempfile.TemporaryDirectory() as tmp:
            iter_dir = Path(tmp) / "iter1"
            self._make_complete_iter(iter_dir, 2)
            (iter_dir / "positions.csv").unlink()
            self.assertFalse(jm.iteration_is_complete(iter_dir, 2))

    def test_empty_alpha_is_false(self):
        with tempfile.TemporaryDirectory() as tmp:
            iter_dir = Path(tmp) / "iter1"
            self._make_complete_iter(iter_dir, 2)
            (iter_dir / "alpha.csv").write_text("")
            self.assertFalse(jm.iteration_is_complete(iter_dir, 2))

    def test_missing_one_persons_embedding_is_false(self):
        with tempfile.TemporaryDirectory() as tmp:
            iter_dir = Path(tmp) / "iter1"
            self._make_complete_iter(iter_dir, 3)
            (iter_dir / "refit" / "embeddings" / "person2.csv").unlink()
            self.assertFalse(jm.iteration_is_complete(iter_dir, 3))

    def test_nonexistent_iteration_is_false(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertFalse(jm.iteration_is_complete(Path(tmp) / "iter1", 2))


class TestFindResumeState(unittest.TestCase):
    def _make_complete_iter(self, iter_dir, n_people, alphas, positions):
        emb_dir = iter_dir / "refit" / "embeddings"
        emb_dir.mkdir(parents=True)
        for i in range(n_people):
            (emb_dir / f"person{i}.csv").write_text("item,dim_0\na,1.0\n")
        pos_text = "position\n" + "\n".join(str(p) for p in positions) + "\n"
        (iter_dir / "positions.csv").write_text(pos_text)
        alpha_text = "alpha\n" + "\n".join(str(a) for a in alphas) + "\n"
        (iter_dir / "alpha.csv").write_text(alpha_text)

    def test_no_prior_iterations_starts_fresh(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            orig_dir = work_dir / "setup" / "original_embeddings"
            start_t, positions, alphas, warm_start_dir, old_pos, old_alpha = jm.find_resume_state(
                work_dir, 6, 2, orig_dir
            )
            self.assertEqual(start_t, 1)
            self.assertIsNone(positions)
            self.assertEqual(alphas, [1.0, 1.0])
            self.assertEqual(warm_start_dir, orig_dir)
            self.assertIsNone(old_pos)
            self.assertIsNone(old_alpha)

    def test_resumes_after_last_complete_iteration(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            self._make_complete_iter(work_dir / "iter1", 2, [1.1, 1.2], [0.1, -0.1])
            self._make_complete_iter(work_dir / "iter2", 2, [1.3, 1.4], [0.2, -0.2])
            start_t, positions, alphas, warm_start_dir, old_pos, old_alpha = jm.find_resume_state(
                work_dir, 6, 2, work_dir / "setup" / "original_embeddings"
            )
            self.assertEqual(start_t, 3)
            self.assertEqual(positions, [0.2, -0.2])
            self.assertEqual(alphas, [1.3, 1.4])
            self.assertEqual(warm_start_dir, work_dir / "iter2" / "refit" / "embeddings")
            self.assertEqual(old_pos, work_dir / "iter2" / "positions.csv")
            self.assertEqual(old_alpha, work_dir / "iter2" / "alpha.csv")

    def test_stops_at_first_gap_does_not_skip_over_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            self._make_complete_iter(work_dir / "iter1", 2, [1.1, 1.2], [0.1, -0.1])
            # iter2 deliberately left incomplete (no files at all)
            self._make_complete_iter(work_dir / "iter3", 2, [1.9, 1.9], [0.9, -0.9])
            start_t, positions, alphas, warm_start_dir, old_pos, old_alpha = jm.find_resume_state(
                work_dir, 6, 2, work_dir / "setup" / "original_embeddings"
            )
            self.assertEqual(start_t, 2)  # resume right after iter1, not iter3
            self.assertEqual(alphas, [1.1, 1.2])

    def test_already_past_n_outer(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            self._make_complete_iter(work_dir / "iter1", 2, [1.1, 1.2], [0.1, -0.1])
            self._make_complete_iter(work_dir / "iter2", 2, [1.3, 1.4], [0.2, -0.2])
            start_t, positions, alphas, warm_start_dir, old_pos, old_alpha = jm.find_resume_state(
                work_dir, 2, 2, work_dir / "setup" / "original_embeddings"
            )
            self.assertEqual(start_t, 3)
            self.assertGreater(start_t, 2)  # caller interprets this as "nothing left to run"


class TestBwNrd0(unittest.TestCase):
    """Verified against R's own bw.nrd0() output on this exact vector --
    see condor_joint_manifold_workflow.py's own docstring for why this
    needs to match R bit-for-bit, not just approximately."""

    def test_matches_r_reference_value(self):
        x = [-0.6264538107, 0.1836433242, -0.8356286124, 1.5952808021, 0.3295077718,
             -0.8204683841, 0.4874290524, 0.7383247051, 0.5757813517, -0.3053883872,
             1.5117811685, 0.3898432364, -0.6212405805, -2.2146998872, 1.1249309181,
             -0.0449336090, -0.0161902631, 0.9438362107, 0.8212211951, 0.5939013212,
             0.9189773716, 0.7821363007, 0.0745649834, -1.9893516959]
        self.assertAlmostEqual(jm.bw_nrd0(x), 0.4184064851, places=9)


class TestRQuantileType7(unittest.TestCase):
    def test_median_of_odd_length(self):
        self.assertAlmostEqual(jm.r_quantile_type7([1.0, 2.0, 3.0], 0.5), 2.0)

    def test_quartiles_of_known_vector(self):
        x = sorted([1.0, 2.0, 3.0, 4.0])
        self.assertAlmostEqual(jm.r_quantile_type7(x, 0.25), 1.75)
        self.assertAlmostEqual(jm.r_quantile_type7(x, 0.75), 3.25)


class TestSmoothedEmbeddingAt(unittest.TestCase):
    def test_weights_sum_to_one_recovers_constant_embedding(self):
        # If every pool member has the IDENTICAL embedding, the weighted
        # average must equal that same embedding regardless of bandwidth/t.
        rows = [[1.0, 2.0], [3.0, 4.0]]
        aligned_list = [rows, rows, rows]
        result = jm.smoothed_embedding_at(0.3, [-1.0, 0.0, 1.0], 0.5, aligned_list)
        for got, expected in zip(result, rows):
            for g, e in zip(got, expected):
                self.assertAlmostEqual(g, e)

    def test_closest_position_dominates_with_narrow_bandwidth(self):
        aligned_list = [[[0.0]], [[10.0]]]
        result = jm.smoothed_embedding_at(0.0, [0.0, 100.0], 0.01, aligned_list)
        self.assertAlmostEqual(result[0][0], 0.0, places=3)

    def test_symmetric_query_point_averages_evenly(self):
        aligned_list = [[[0.0]], [[10.0]]]
        result = jm.smoothed_embedding_at(5.0, [0.0, 10.0], 1000.0, aligned_list)
        self.assertAlmostEqual(result[0][0], 5.0, places=3)


class TestGrandMeanEmbedding(unittest.TestCase):
    def test_averages_across_pool_with_no_weighting(self):
        aligned_list = [[[0.0, 0.0], [2.0, 2.0]], [[10.0, 0.0], [2.0, -2.0]]]
        result = jm.grand_mean_embedding(aligned_list)
        self.assertAlmostEqual(result[0][0], 5.0)
        self.assertAlmostEqual(result[0][1], 0.0)
        self.assertAlmostEqual(result[1][0], 2.0)
        self.assertAlmostEqual(result[1][1], 0.0)

    def test_identical_pool_members_recover_that_embedding(self):
        rows = [[1.0, 2.0], [3.0, 4.0]]
        result = jm.grand_mean_embedding([rows, rows, rows])
        for got, expected in zip(result, rows):
            for g, e in zip(got, expected):
                self.assertAlmostEqual(g, e)


class TestReadAlphaCsv(unittest.TestCase):
    def test_reads_alpha_column_in_row_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "alpha.csv"
            path.write_text("log_alpha,alpha,bandwidth\n0.1,1.105,0.2\n-0.3,0.741,0.2\n")
            self.assertEqual(jm.read_alpha_csv(path), [1.105, 0.741])


class TestReadDimCsv(unittest.TestCase):
    def test_reads_rows_in_file_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "aligned.csv"
            path.write_text("dim_0,dim_1\n1.0,2.0\n3.0,4.0\n")
            rows = jm.read_dim_csv(path)
            self.assertEqual(rows, [[1.0, 2.0], [3.0, 4.0]])


class TestWriteSmoothedOutputs(unittest.TestCase):
    def test_skips_gracefully_when_aligned_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            (work_dir / "iter2").mkdir(parents=True)
            # No aligned/ directory created -- simulates a run from before
            # the transfer_output_files fix.
            jm.write_smoothed_outputs(work_dir, 2, ["p1", "p2"], ["a", "b"], [0.1, -0.1])
            self.assertFalse((work_dir / "final_smoothed_embeddings.csv").exists())
            self.assertFalse((work_dir / "final_grand_mean_embedding.csv").exists())

    def test_writes_expected_files_when_aligned_present(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            aligned_dir = work_dir / "iter2" / "aligned"
            aligned_dir.mkdir(parents=True)
            (aligned_dir / "person0.csv").write_text("dim_0,dim_1\n1.0,2.0\n3.0,4.0\n")
            (aligned_dir / "person1.csv").write_text("dim_0,dim_1\n5.0,6.0\n7.0,8.0\n")

            jm.write_smoothed_outputs(work_dir, 2, ["p1", "p2"], ["itemA", "itemB"], [0.1, -0.1])

            self.assertTrue((work_dir / "final_smoothed_embeddings.csv").exists())
            with open(work_dir / "final_smoothed_embeddings.csv", newline="") as f:
                rows = list(csv.DictReader(f))
            self.assertEqual(len(rows), 4)  # 2 participants x 2 items
            self.assertEqual({r["worker_id"] for r in rows}, {"p1", "p2"})

            # Alpha is no longer written here -- it's decoupled from position
            # now, so final_alpha.csv is written directly in main() from the
            # per-person values already in memory, with no position-dependent
            # computation needed.
            self.assertFalse((work_dir / "final_smoothed_alpha.csv").exists())

            self.assertTrue((work_dir / "final_grand_mean_embedding.csv").exists())
            with open(work_dir / "final_grand_mean_embedding.csv", newline="") as f:
                gm_rows = list(csv.DictReader(f))
            self.assertEqual(len(gm_rows), 2)  # one row per item, no worker_id (same for everyone)
            self.assertEqual({r["item"] for r in gm_rows}, {"itemA", "itemB"})
            gm_itemA = next(r for r in gm_rows if r["item"] == "itemA")
            self.assertAlmostEqual(float(gm_itemA["dim_0"]), 3.0)  # mean(1.0, 5.0)
            self.assertAlmostEqual(float(gm_itemA["dim_1"]), 4.0)  # mean(2.0, 6.0)


if __name__ == "__main__":
    unittest.main()
