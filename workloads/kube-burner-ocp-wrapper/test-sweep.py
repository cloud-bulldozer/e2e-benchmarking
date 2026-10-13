#!/usr/bin/env python3
"""Local-only wrapper tests: python3 workloads/kube-burner-ocp-wrapper/test-sweep.py."""

import json
import os
import re
from pathlib import Path
import shutil
import signal
import subprocess
import tarfile
import tempfile
import time
import unittest

SOURCE = Path(__file__).resolve().parent
SWEEP_HOOK = """if [[ -n ${QPS_LIST:-} ]]; then
  exec bash "$(dirname "${BASH_SOURCE[0]}")/sweep.sh" "$@"
fi

"""


class Sweep(unittest.TestCase):
    """Run the wrapper against stubbed kube-burner-ocp, oc, curl and index.sh."""

    def setUp(self):
        """Copy the wrapper into a temporary tree and put stub binaries first on PATH."""
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.wrapper = self.root / "workloads/kube-burner-ocp-wrapper"
        self.wrapper.mkdir(parents=True)
        for name in ("run.sh", "sweep.sh"):
            shutil.copy(SOURCE / name, self.wrapper / name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.write_bin("kube-burner-ocp", r"""#!/usr/bin/env python3
import json, os, pathlib, sys, time
args = sys.argv[1:]
uuid = args[args.index('--uuid') + 1]
with open(os.environ['CALLS'], 'a') as f:
    f.write(json.dumps(args) + '\n')
pathlib.Path('collected-metrics-' + uuid).mkdir()
if '-qps' in uuid:
    assert not pathlib.Path(os.environ['NAMESPACE']).exists()
pathlib.Path(os.environ['NAMESPACE']).write_text(uuid)
if os.environ.get('BLOCK'):
    time.sleep(60)
sys.exit(7 if ('--qps=' + os.environ.get('FAIL_QPS', '')) in args else 0)
""")
        archive = self.root / "binary.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(self.bin / "kube-burner-ocp", arcname="kube-burner-ocp")
        self.write_bin("curl", '#!/bin/bash\ncase "$*" in *https://es.invalid*) echo \"{}\" ;; *) cat "$ARCHIVE" ;; esac\n')
        self.write_bin("oc", r"""#!/usr/bin/env python3
import json, os, pathlib, sys, time
with open(os.environ['CLEANUPS'], 'a') as f:
    f.write(json.dumps(sys.argv[1:]) + '\n')
if os.environ.get('BLOCK_CLEANUP'):
    time.sleep(60)
if os.environ.get('FAIL_CLEANUP'):
    sys.exit(9)
namespace = pathlib.Path(os.environ['NAMESPACE'])
assert 'kube-burner.io/uuid=' + namespace.read_text() in sys.argv
namespace.unlink()
""")
        utils = self.root / "utils"
        utils.mkdir()
        (utils / "index.sh").write_text('#!/bin/bash\nexit 0\n')
        (utils / "index.sh").chmod(0o755)
        self.env = {
            "PATH": str(self.bin) + ":" + os.environ["PATH"],
            "HOME": str(self.root), "WORKLOAD": "node-density", "UUID": "test",
            "KUBE_DIR": str(self.bin), "ARCHIVE": str(archive),
            "CALLS": str(self.root / "calls"), "CLEANUPS": str(self.root / "cleanups"),
            "NAMESPACE": str(self.root / "namespace"), "SWEEP_SLEEP": "0",
            "EXTRA_FLAGS": "--local-indexing --metrics-endpoint=metrics.yml --pods-per-node=245",
        }

    def write_bin(self, name, content):
        """Write an executable stub called ``name`` into the stub bin directory."""
        path = self.bin / name
        path.write_text(content)
        path.chmod(0o755)

    def run_wrapper(self, **variables):
        """Run run.sh with the stub environment plus ``variables``."""
        return subprocess.run(["bash", "run.sh"], cwd=self.wrapper,
                              env={**self.env, **variables}, capture_output=True,
                              text=True, timeout=15)

    def rows(self, name):
        """Return the JSON lines a stub appended to the file ``name``."""
        return [json.loads(line) for line in (self.root / name).read_text().splitlines()]

    def summary(self):
        """Return the sweep summary written for the base UUID."""
        return json.loads((self.wrapper / "sweep-test.json").read_text())

    def test_single_run_parity(self):
        """Without QPS_LIST, run.sh behaves exactly like run.sh without the sweep hook."""
        current = (SOURCE / "run.sh").read_text()
        self.assertEqual(current.count(SWEEP_HOOK), 1, "sweep hook not found in run.sh")
        (self.wrapper / "baseline.sh").write_text(current.replace(SWEEP_HOOK, ""))
        for failure in ("", "20"):
            with self.subTest(failure=failure):
                baseline = subprocess.run(["bash", "baseline.sh"], cwd=self.wrapper,
                                          env={**self.env, "FAIL_QPS": failure},
                                          capture_output=True, text=True, timeout=15)
                shutil.rmtree(self.wrapper / "collected-metrics-test")
                actual = self.run_wrapper(FAIL_QPS=failure)
                self.assertEqual(actual.returncode, baseline.returncode)
                self.assertEqual(actual.stdout, baseline.stdout)
                self.assertEqual(actual.stderr, baseline.stderr)
                self.assertEqual(self.rows("calls")[-1], self.rows("calls")[-2])
                shutil.rmtree(self.wrapper / "collected-metrics-test")
        self.assertFalse((self.root / "cleanups").exists())
        self.assertFalse((self.wrapper / "sweep-test.json").exists())

    def test_sweep(self):
        """Each step runs with its own UUID, QPS and burst, is cleaned up and is recorded."""
        result = self.run_wrapper(QPS_LIST="2 4 6", ES_SERVER="https://es.invalid", ES_INDEX="test-index", GC="false")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        rows = self.summary()
        self.assertEqual([r["qps"] for r in rows], [2, 4, 6])
        for qps, args, row, cleanup in zip((2, 4, 6), self.rows("calls"), rows, self.rows("cleanups")):
            uuid = f"test-qps{qps}"
            self.assertIn(f"--qps={qps}", args)
            self.assertIn(f"--burst={qps}", args)
            self.assertEqual(args[args.index("--uuid") + 1], uuid)
            self.assertIn("--metrics-endpoint=metrics.yml", args)
            self.assertIn("--local-indexing", args)
            self.assertIn("--es-server=https://es.invalid", args)
            self.assertIn("--es-index=test-index", args)
            self.assertIn("--gc=false", args)
            self.assertEqual(row["uuid"], uuid)
            self.assertEqual(row["workload"], "node-density")
            self.assertEqual(row["burst"], qps)
            self.assertEqual(row["rc"], 0)
            self.assertEqual(row["cleanup_rc"], 0)
            self.assertLessEqual(row["start_epoch"], row["end_epoch"])
            self.assertTrue((self.wrapper / row["log"]).exists())
            self.assertTrue((self.wrapper / f"collected-metrics-{uuid}").is_dir())
            self.assertIn(f"kube-burner.io/uuid={uuid}", cleanup)
            self.assertIn("--wait=true", cleanup)
            self.assertIn("--timeout=300s", cleanup)
        self.assertFalse((self.root / "namespace").exists())

    def test_failure_stops_and_explicit_burst(self):
        """A failed step is cleaned up and stops the sweep; an explicit BURST applies to every step."""
        result = self.run_wrapper(QPS_LIST="2 4 6", BURST="12", FAIL_QPS="4")
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual([r["rc"] for r in self.summary()], [0, 7])
        self.assertEqual(len(self.rows("calls")), 2)
        self.assertEqual(len(self.rows("cleanups")), 2)
        self.assertTrue(all("--burst=12" in args for args in self.rows("calls")))

    def test_cleanup_failure_stops(self):
        """A failed namespace cleanup stops the sweep with the cleanup exit code."""
        result = self.run_wrapper(QPS_LIST="2 4", FAIL_CLEANUP="1")
        self.assertEqual(result.returncode, 9, result.stderr)
        self.assertEqual(len(self.rows("calls")), 1)
        self.assertEqual(self.summary()[0]["cleanup_rc"], 9)

    def test_cleanup_timeout(self):
        """A cleanup that exceeds SWEEP_CLEANUP_TIMEOUT stops the sweep with exit code 124."""
        result = self.run_wrapper(QPS_LIST="2 4", BLOCK_CLEANUP="1", SWEEP_CLEANUP_TIMEOUT="1")
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertEqual(len(self.rows("calls")), 1)
        self.assertEqual(self.summary()[0]["cleanup_rc"], 124)

    def test_jq_arguments_are_not_keywords(self):
        """jq variable names avoid keywords, which jq 1.6 rejects and newer jq accepts."""
        keywords = set("if then else elif end and or not as def reduce foreach "
                       "try catch label break import include module "
                       "true false null".split())
        arguments = re.findall(r"--arg(?:json)?\s+(\w+)", (SOURCE / "sweep.sh").read_text())
        self.assertTrue(arguments)
        self.assertFalse(keywords.intersection(arguments))

    def test_failed_record_removes_temporary_file(self):
        """A failed summary write stops the sweep, keeps earlier rows and removes the temporary file."""
        real_jq = shutil.which("jq")
        self.assertIsNotNone(real_jq)
        self.write_bin("jq", r"""#!/usr/bin/env python3
import os, sys
args = sys.argv[1:]
if '--argjson' in args and args[args.index('qps') + 1] == '4':
    print('partial output')
    sys.exit(3)
os.execv(os.environ['REAL_JQ'], [os.environ['REAL_JQ'], *args])
""")
        result = self.run_wrapper(QPS_LIST="2 4 6", REAL_JQ=real_jq)
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual([row["qps"] for row in self.summary()], [2])
        self.assertFalse((self.wrapper / "sweep-test.json.tmp").exists())
        self.assertEqual(len(self.rows("calls")), 2)
        self.assertEqual(len(self.rows("cleanups")), 2)

    def test_failed_summary_rename_removes_temporary_file(self):
        """A failed summary rename stops the sweep and removes the temporary file."""
        self.write_bin("mv", "#!/bin/bash\nexit 8\n")
        result = self.run_wrapper(QPS_LIST="2 4")
        self.assertEqual(result.returncode, 8, result.stderr)
        self.assertEqual(self.summary(), [])
        self.assertFalse((self.wrapper / "sweep-test.json.tmp").exists())
        self.assertEqual(len(self.rows("calls")), 1)
        self.assertEqual(len(self.rows("cleanups")), 1)

    def test_existing_summary_is_preserved(self):
        """An existing summary for the UUID stops the sweep before any step and is left untouched."""
        path = self.wrapper / "sweep-test.json"
        path.write_text("[{}]\n")
        self.assertNotEqual(self.run_wrapper(QPS_LIST="2 4").returncode, 0)
        self.assertEqual(path.read_text(), "[{}]\n")
        self.assertFalse((self.root / "calls").exists())

    def test_invalid_input(self):
        """Duplicate, zero, non-numeric, zero-padded and blank QPS lists fail before any step."""
        for values in ("2 2", "0 4", "2 nope", "02", " "):
            with self.subTest(values=values):
                self.assertNotEqual(self.run_wrapper(QPS_LIST=values).returncode, 0)
        self.assertFalse((self.root / "calls").exists())

    def test_interrupt_cleans_and_records(self):
        """SIGTERM during a step cleans up that step and records exit code 143."""
        self.interrupt(signal.SIGTERM, 143)

    def test_sigint_cleans_and_records(self):
        """SIGINT during a step cleans up that step and records exit code 130."""
        self.interrupt(signal.SIGINT, 130)

    def interrupt(self, signum, expected_rc):
        """Send ``signum`` during the first step and check its cleanup and recorded ``expected_rc``."""
        process = subprocess.Popen(["bash", "run.sh"], cwd=self.wrapper,
                                   env={**self.env, "QPS_LIST": "2 4", "BLOCK": "1"},
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 10
            while not (self.root / "namespace").exists():
                if time.monotonic() > deadline:
                    self.fail("Stub did not start")
                time.sleep(0.02)
            process.send_signal(signum)
            self.assertEqual(process.wait(timeout=10), expected_rc)
            self.assertEqual(self.summary()[0]["rc"], expected_rc)
            self.assertEqual(len(self.rows("calls")), 1)
            self.assertFalse((self.root / "namespace").exists())
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


if __name__ == "__main__":
    unittest.main(verbosity=2)
