"""Unit tests for condor_individual_embeddings_workflow.py's pure logic
(CSV reading/filtering, worker grouping, output aggregation) -- everything
that doesn't require a real HTCondor cluster or condor_submit/condor_wait.

Run locally with:
    python3 -m unittest inst/condor/test_condor_individual_embeddings_workflow.py -v

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
import condor_individual_embeddings_workflow as ie  # noqa: E402


class TestCsvHelpers(unittest.TestCase):
    def test_read_triplet_rows_requires_worker_id_column(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "bad.csv"
            path.write_text("Center,Left,Right,Answer\nx,y,z,y\n")
            with self.assertRaises(SystemExit):
                ie.read_triplet_rows(path)

    def test_read_triplet_rows_requires_hard_columns(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "bad.csv"
            path.write_text("worker_id,Center,Left\np1,a,b\n")  # missing Right, Answer
            with self.assertRaises(SystemExit):
                ie.read_triplet_rows(path)

    def test_read_triplet_rows_trims_to_needed_columns(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "full.csv"
            path.write_text(
                "head,winner,loser,worker_id,rt,Center,Left,Right,Answer,sampleAlg,sampleSet\n"
                "1,2,3,p1,1000,a,b,c,b,random,train\n"
            )
            fieldnames, rows = ie.read_triplet_rows(path)
            self.assertEqual(
                set(fieldnames),
                {"worker_id", "Center", "Left", "Right", "Answer", "sampleSet"},
            )
            self.assertNotIn("head", rows[0])
            self.assertNotIn("rt", rows[0])

    def test_read_triplet_rows_tolerates_missing_sampleset(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "no_sampleset.csv"
            path.write_text("worker_id,Center,Left,Right,Answer\np1,a,b,c,b\n")
            fieldnames, rows = ie.read_triplet_rows(path)  # must not raise
            self.assertNotIn("sampleSet", fieldnames)

    def test_group_rows_by_worker(self):
        rows = [
            {"worker_id": "p1", "Answer": "b"},
            {"worker_id": "p2", "Answer": "c"},
            {"worker_id": "p1", "Answer": "a"},
        ]
        grouped = ie.group_rows_by_worker(rows)
        self.assertEqual(len(grouped["p1"]), 2)
        self.assertEqual(len(grouped["p2"]), 1)
        self.assertNotIn("p3", grouped)

    def test_write_filtered_csv_writes_only_that_workers_rows(self):
        fieldnames = ["worker_id", "Center", "Left", "Right", "Answer"]
        rows = [
            {"worker_id": "p1", "Center": "a", "Left": "b", "Right": "c", "Answer": "b"},
            {"worker_id": "p1", "Center": "d", "Left": "e", "Right": "f", "Answer": "e"},
        ]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "worker0.csv"
            ie.write_filtered_csv(path, fieldnames, rows)
            with open(path, newline="") as f:
                out_rows = list(csv.DictReader(f))
            self.assertEqual(len(out_rows), 2)
            self.assertTrue(all(r["worker_id"] == "p1" for r in out_rows))


class TestAggregateEmbeddings(unittest.TestCase):
    def test_aggregate_embeddings_concatenates_in_job_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            stage1_dir = work_dir / "stage1_fit"
            stage1_dir.mkdir()

            (stage1_dir / "embedding_worker0.csv").write_text(
                "worker_id,item,dim_0,dim_1\np2,itemA,1.0,2.0\np2,itemB,3.0,4.0\n"
            )
            (stage1_dir / "embedding_worker1.csv").write_text(
                "worker_id,item,dim_0,dim_1\np1,itemA,5.0,6.0\np1,itemB,7.0,8.0\n"
            )

            jobs = [
                ("worker0.csv", "embedding_worker0.csv", "p2", 1),
                ("worker1.csv", "embedding_worker1.csv", "p1", 2),
            ]
            out_path = ie.aggregate_embeddings(work_dir, stage1_dir, jobs)

            with open(out_path, newline="") as f:
                rows = list(csv.DictReader(f))

            self.assertEqual(rows[0]["worker_id"], "p2")
            self.assertEqual(rows[2]["worker_id"], "p1")
            self.assertEqual(len(rows), 4)
            self.assertEqual(list(rows[0].keys()), ["worker_id", "item", "dim_0", "dim_1"])

    def test_aggregate_embeddings_exits_on_missing_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            stage1_dir = work_dir / "stage1_fit"
            stage1_dir.mkdir()
            jobs = [("worker0.csv", "embedding_worker0.csv", "p1", 1)]
            with self.assertRaises(SystemExit):
                ie.aggregate_embeddings(work_dir, stage1_dir, jobs)


if __name__ == "__main__":
    unittest.main()
