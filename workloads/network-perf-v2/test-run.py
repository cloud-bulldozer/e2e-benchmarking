#!/usr/bin/env python3
"""Local-only tests of run.sh: python3 workloads/network-perf-v2/test-run.py.

run.sh runs in a temporary copy of the repository with fake oc, kubectl, curl and k8s-netperf. The fakes
keep node labels in a state file and log every call; nothing reaches a real cluster.
"""

import io
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
import unittest
import uuid

SOURCE = Path(__file__).resolve().parent
REPO = SOURCE.parent.parent

# One fake for every tool; the tool is the file name (anything else is k8s-netperf).
FAKE = r'''#!@PYTHON@ -I
import json, os, sys, time

STATE = os.environ["FAKE_STATE"]
NAME = os.path.basename(sys.argv[0])
TOOL = NAME if NAME in ("oc", "kubectl", "curl") else "netperf"
VERSION = "@VERSION@"
ARGS = sys.argv[1:]


def log(**entry):
    entry.update(tool=TOOL, argv=ARGS, pid=os.getpid(), pgid=os.getpgid(0), sid=os.getsid(0), t=time.time())
    with open(os.path.join(STATE, "log.jsonl"), "a") as f:
        f.write(json.dumps(entry) + "\n")


def load(name, default):
    try:
        with open(os.path.join(STATE, name)) as f:
            return json.load(f)
    except FileNotFoundError:
        return default


def save(name, data):
    path = os.path.join(STATE, name)
    with open(path + ".tmp", "w") as f:
        json.dump(data, f)
    os.replace(path + ".tmp", path)


BEHAVIOR = load("behavior.json", {})


def matches(rule):
    return rule.get("tool", TOOL) == TOOL and all(token in " ".join(ARGS) for token in rule.get("match", []))


def first(kind):
    for index, rule in enumerate(BEHAVIOR.get(kind, [])):
        if matches(rule):
            return index, rule
    return None, None


def apply_mutations():
    used = load("used.json", {})
    for index, rule in enumerate(BEHAVIOR.get("mutate", [])):
        key = str(index)
        if not matches(rule) or used.get(key, 0) >= rule.get("times", 1):
            continue
        used[key] = used.get(key, 0) + 1
        save("used.json", used)
        state = load("nodes.json", None)
        node = state["nodes"][rule["node"]]
        action = rule["action"]
        if action == "set":
            node["labels"]["netperf"] = rule["value"]
            node["owners"]["netperf"] = [rule["manager"]]
        elif action == "co-own":
            node["owners"].setdefault("netperf", []).append(rule["manager"])
        elif action == "recreate":
            node["uid"] = node["uid"] + "-recreated"
        if rule.get("manager") and rule["manager"] not in node["managers"]:
            node["managers"].append(rule["manager"])
        node["rv"] += 1
        save("nodes.json", state)


def selector_match(labels, selector):
    for term in selector.split(","):
        if not term:
            continue
        if "!=" in term:
            key, value = term.split("!=", 1)
            if labels.get(key) == value:
                return False
        elif "=" in term:
            key, value = term.split("=", 1)
            if labels.get(key) != value:
                return False
        elif term not in labels:
            return False
    return True


def option(name):
    if name in ARGS:
        return ARGS[ARGS.index(name) + 1]
    for arg in ARGS:
        if arg.startswith(name + "="):
            return arg.split("=", 1)[1]
    return None


def positional():
    values, skip = [], False
    for arg in ARGS:
        if skip:
            skip = False
        elif arg in ("-l", "-o", "-n", "--kubeconfig"):
            skip = True
        elif not arg.startswith("-"):
            values.append(arg)
    return values


def cluster():
    state = load("nodes.json", {"order": [], "nodes": {}})
    nodes = state["nodes"]
    words = positional()
    if words[:2] in (["get", "nodes"], ["get", "node"]):
        output = option("-o") or ""
        if len(words) > 2:
            node = nodes.get(words[2])
            if node is None:
                sys.stderr.write('Error from server (NotFound): nodes "%s" not found\n' % words[2])
                sys.exit(1)
            if "managedFields" in output:
                owners = node["owners"].get("netperf", [])
                sys.stdout.write("%s\n%s\n%s\n" % (node["uid"], node["rv"], node["labels"].get("netperf", "")))
                for manager in node["managers"]:
                    sys.stdout.write("%s\t%s\n" % (manager, "{}" if manager in owners else ""))
            return
        selected = [n for n in state["order"] if selector_match(nodes[n]["labels"], option("-l") or "")]
        for name in selected:
            node = nodes[name]
            if output.startswith("jsonpath="):
                sys.stdout.write("%s\t%s\t%s\n" % (name, node["rv"], node["labels"].get("netperf", "")))
            elif output == "name" or output.startswith("custom-columns="):
                sys.stdout.write(("node/%s\n" if output == "name" else "%s\n") % name)
            else:
                sys.stdout.write("%s   Ready   worker   1d   v1.30.0\n" % name)
        return
    if words[:1] == ["label"]:
        kind = words[1]
        rest = words[2:]
        if "/" in kind:
            targets, specs = [kind.split("/", 1)[1]], rest
        else:
            specs = [w for w in rest if "=" in w or w.endswith("-")]
            targets = [w for w in rest if w not in specs]
        if option("-l") is not None:
            targets = [n for n in state["order"] if selector_match(nodes[n]["labels"], option("-l"))]
        manager = option("--field-manager") or "kubectl-label"
        for name in targets:
            node = nodes.get(name)
            if node is None:
                sys.stderr.write('Error from server (NotFound): nodes "%s" not found\n' % name)
                sys.exit(1)
            for spec in specs:
                if "=" in spec:
                    key = spec.split("=", 1)[0]
                    if key in node["labels"] and "--overwrite" not in ARGS:
                        sys.stderr.write("error: '%s' already has a value (%s), and --overwrite is false\n"
                                         % (key, node["labels"][key]))
                        sys.exit(1)
            resource_version = option("--resource-version")
            if resource_version is not None and resource_version != str(node["rv"]):
                sys.stderr.write('Error from server (Conflict): Operation cannot be fulfilled on nodes "%s": the '
                                 'object has been modified; please apply your changes to the latest version and '
                                 'try again\n' % name)
                sys.exit(1)
            for spec in specs:
                if spec.endswith("-") and "=" not in spec:
                    node["labels"].pop(spec[:-1], None)
                    node["owners"].pop(spec[:-1], None)
                else:
                    key, value = spec.split("=", 1)
                    node["labels"][key] = value
                    node["owners"][key] = [manager]
                    if manager not in node["managers"]:
                        node["managers"].append(manager)
            node["rv"] += 1
            if option("-o") == "jsonpath={.metadata.uid}":
                sys.stdout.write(node["uid"])
            else:
                sys.stdout.write("node/%s labeled\n" % name)
        save("nodes.json", state)
        return
    sys.stdout.write("fake %s %s\n" % (TOOL, " ".join(ARGS)))


def netperf():
    if ARGS == ["--version"]:
        log(event="version")
        print("Version: %s\nGit Commit: fake" % VERSION)
        return
    config = BEHAVIOR.get("netperf", {})
    with open("result.csv", "w") as f:
        f.write("Driver,Scenario\nnetperf,TCP_STREAM\n")
    log(event="run", version=VERSION)
    apply_mutations()
    log(event="exit", code=config.get("exit", 0))
    sys.exit(config.get("exit", 0))


def curl():
    log(event="call")
    if "--retry-all-errors" in ARGS:
        with open(os.path.join(STATE, "netperf.tar.gz"), "rb") as f:
            sys.stdout.buffer.write(f.read())
        return
    sys.stdout.write("{}\n")


def main():
    if TOOL == "netperf":
        return netperf()
    if TOOL == "curl":
        return curl()
    log(event="call")
    apply_mutations()
    index, rule = first("fail")
    if rule:
        sys.stderr.write(rule.get("stderr", "fake failure") + "\n")
        sys.exit(rule.get("exit", 1))
    cluster()


main()
'''

NODES = {
    "m1": {"node-role.kubernetes.io/master": "", "node-role.kubernetes.io/control-plane": ""},
    "w1": {"node-role.kubernetes.io/worker": ""},
    "w2": {"node-role.kubernetes.io/worker": ""},
    "w3": {"node-role.kubernetes.io/worker": ""},
    "i1": {"node-role.kubernetes.io/worker": "", "node-role.kubernetes.io/infra": ""},
}

DEFAULT_ARGV = ["--clean=true", "--config=smoke.yaml", "--debug=true", "--local=false", "--metrics=true",
                "--tcp-tolerance=70", "--uuid=test-uuid", "--vm=false", "--pod=true", "--udnl2=false", "--udnl3=false"]

# Every input the MicroShift role (ansible/roles/run-network-perf/tasks/iteration.yml) sets.
ROLE_INPUTS = {
    "PLATFORM": "microshift", "LOCAL": "true", "POD": "true", "VM": "false", "USE_VIRTCTL": "", "UDNL2": "false",
    "UDNL3": "false", "BRIDGE": "", "BRIDGE_CONFIG": "", "LOCALNET": "", "LOCALNET_CONFIG": "",
    "EXTERNAL_SERVER_ADDRESS": "", "ALL_SCENARIOS": "true", "DEBUG": "true", "TOLERANCE": "70",
    "WORKLOAD": "smoke.yaml", "WORKLOAD_NAME": "k8s-netperf", "NETPERF_VERSION": "v0.1.43",
    "NETPERF_FILENAME": "k8s-netperf", "NETPERF_URL": "", "OS": "Linux", "UUID": "test-uuid", "CLEAN_UP": "false",
    "TEST_TIMEOUT": "60", "METRICS": "false", "PROMETHEUS_URL": "", "ES_SERVER": "", "PROW_JOB_ID": "",
    "BUILD_ID": "", "AIRFLOW_CTX_DAG_ID": "",
}
ROLE_ARGV = ["--clean=false", "--config=smoke.yaml", "--debug=true", "--local=true", "--metrics=false",
             "--tcp-tolerance=70", "--uuid=test-uuid", "--vm=false", "--pod=true", "--udnl2=false", "--udnl3=false"]


def session_members(sid):
    """Live processes (not zombies) of session sid."""
    members = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            stat = (entry / "stat").read_text()
        except OSError:
            continue
        fields = stat[stat.rindex(")") + 2:].split()
        if int(fields[3]) == sid and fields[0] not in ("Z", "X"):
            members.append(int(entry.name))
    return members


class Result:
    def __init__(self, rc, output, elapsed, leftovers):
        self.rc, self.output, self.elapsed, self.leftovers = rc, output, elapsed, leftovers


class Started:
    """A running run.sh, its own session leader, with its output collected in the background."""

    def __init__(self, process):
        self.process, self.pid = process, process.pid
        self.started = time.monotonic()
        self.output = io.BytesIO()
        stream = process.stdout
        assert stream is not None
        self.reader = threading.Thread(target=shutil.copyfileobj, args=(stream, self.output), daemon=True)
        self.reader.start()


class RunSh(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.workload = self.root / "workloads/network-perf-v2"
        self.workload.mkdir(parents=True)
        for path in SOURCE.iterdir():
            if path.suffix in (".sh", ".yaml"):
                shutil.copy(path, self.workload / path.name)
        (self.root / "utils").mkdir()
        for name in ("common.sh", "index.sh"):
            shutil.copy(REPO / "utils" / name, self.root / "utils" / name)
        self.bin = self.root / "bin"
        self.state = self.root / "state"
        self.bin.mkdir()
        self.state.mkdir()
        for tool in ("oc", "kubectl", "curl"):
            self.write_fake(self.bin / tool, "unused")
        self.write_fake(self.workload / "k8s-netperf", "v0.1.43")
        self.make_tarball("k8s-netperf", "v9.9.9-downloaded")
        self.set_nodes()
        self.behavior = {}
        self.tmp = self.root / "tmp"
        self.tmp.mkdir()
        self.server_kubeconfig = self.root / "server-kubeconfig"
        self.server_kubeconfig.write_text("apiVersion: v1\nkind: Config\n")
        self.env = {
            "PATH": "%s:%s" % (self.bin, os.environ["PATH"]),
            "HOME": str(self.root), "FAKE_STATE": str(self.state), "TMPDIR": str(self.tmp),
            "KUBECONFIG": str(self.root / "nonexistent-kubeconfig"),
            "UUID": "test-uuid", "TEST_TIMEOUT": "60",
        }
        for tool in ("oc", "kubectl", "curl"):
            self.assertEqual(shutil.which(tool, path=self.env["PATH"]), str(self.bin / tool))

    # -- fixtures --------------------------------------------------------------------------------

    def write_fake(self, path, version):
        path.write_text(FAKE.replace("@PYTHON@", sys.executable).replace("@VERSION@", version))
        path.chmod(0o755)

    def make_tarball(self, name, version):
        source = self.root / "tarball-src"
        source.mkdir(exist_ok=True)
        self.write_fake(source / name, version)
        with tarfile.open(self.state / "netperf.tar.gz", "w:gz") as tar:
            tar.add(source / name, arcname=name)

    def set_nodes(self, extra_labels=None, owners=None):
        state = {"order": list(NODES), "nodes": {}}
        for name, labels in NODES.items():
            labels = dict(labels, **(extra_labels or {}).get(name, {}))
            node_owners = {"netperf": [(owners or {}).get(name, "someone")]} if "netperf" in labels else {}
            managers = ["kubelet"] + [m for ms in node_owners.values() for m in ms]
            state["nodes"][name] = {"uid": "uid-" + name, "rv": 100, "labels": labels,
                                    "owners": node_owners, "managers": managers}
        (self.state / "nodes.json").write_text(json.dumps(state))

    def nodes(self):
        return json.loads((self.state / "nodes.json").read_text())["nodes"]

    def netperf_labels(self):
        return {name: node["labels"].get("netperf") for name, node in self.nodes().items()
                if "netperf" in node["labels"]}

    def log(self):
        path = self.state / "log.jsonl"
        if not path.exists():
            return []
        return [json.loads(line) for line in path.read_text().splitlines()]

    def runs(self):
        return [e for e in self.log() if e["tool"] == "netperf" and e.get("event") == "run"]

    def argv(self):
        runs = self.runs()
        self.assertEqual(len(runs), 1, runs)
        return runs[0]["argv"]

    def cluster_calls(self, after=None):
        calls = [e for e in self.log() if e["tool"] in ("oc", "kubectl", "curl") and e.get("event") == "call"]
        if after is not None:
            calls = [e for e in calls if e["t"] > after]
        return calls

    # -- running run.sh --------------------------------------------------------------------------

    def start(self, **variables):
        (self.state / "behavior.json").write_text(json.dumps(self.behavior))
        env = dict(self.env)
        env.update(variables)
        process = subprocess.Popen(["bash", "run.sh"], cwd=self.workload, env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        run = Started(process)
        self.addCleanup(self.end_run, run)
        return run

    def end_run(self, run):
        self.kill_session(run.pid)
        run.process.wait(timeout=10)
        run.reader.join(timeout=10)
        if run.process.stdout:
            run.process.stdout.close()

    def finish(self, run, limit=120):
        rc = run.process.wait(timeout=limit)
        elapsed = time.monotonic() - run.started
        run.reader.join(timeout=30)
        leftovers = session_members(run.pid)
        deadline = time.monotonic() + 2
        while leftovers and time.monotonic() < deadline:
            time.sleep(0.05)
            leftovers = session_members(run.pid)
        return Result(rc, run.output.getvalue().decode(errors="replace"), elapsed, leftovers)

    def run_sh(self, **variables):
        return self.finish(self.start(**variables))

    def kill_session(self, sid):
        for pid in session_members(sid):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    def assert_clean_end(self, result):
        self.assertEqual(result.leftovers, [], "processes left in run.sh's session")
        self.assertEqual(list(self.tmp.iterdir()), [], "files left in TMPDIR")

    def ci(self):
        """CI variables that make utils/index.sh index; its fixed /tmp paths get unique names and are removed."""
        name = "e2e-netperf-test-%s" % uuid.uuid4().hex[:12]
        self.addCleanup(shutil.rmtree, "/tmp/" + name, True)
        self.addCleanup(Path("/tmp/%s-uuid.txt" % name).unlink, True)
        return {"PROW_JOB_ID": "1234", "JOB_NAME": "job", "BUILD_ID": "7", "UUID": name, "WORKLOAD_NAME": name}

    # -- 1-4: command line in each mode -------------------------------------------------------------

    def test_01_openshift_default(self):
        result = self.run_sh()
        self.assertEqual(result.rc, 0, result.output)
        self.assertEqual(self.argv(), ["--all=true"] + DEFAULT_ARGV)
        self.assertIn("Executing command: timeout 60 ./k8s-netperf --all=true", result.output)
        labels = [e["argv"] for e in self.cluster_calls() if e["argv"][:1] == ["label"]]
        self.assertEqual([a[:3] for a in labels], [["label", "nodes", "w1"], ["label", "nodes", "w2"],
                                                   ["label", "nodes", "w1"], ["label", "nodes", "w2"]])
        self.assertTrue(all(any(a.startswith("--field-manager=e2e-netperf-") for a in call) for call in labels[:2]))
        self.assertNotIn("--overwrite", sum(labels, []))
        self.assertEqual(self.netperf_labels(), {})
        self.assert_clean_end(result)

    def test_02_microshift_same_node(self):
        self.set_nodes({"w1": {"netperf": "client"}})
        result = self.run_sh(**ROLE_INPUTS)
        self.assertEqual(result.rc, 0, result.output)
        self.assertEqual(self.argv(), ROLE_ARGV)
        self.assertEqual([e for e in self.cluster_calls() if "label" in e["argv"]], [])
        self.assertEqual(self.netperf_labels(), {"w1": "client"})
        self.assert_clean_end(result)

    def test_03_microshift_cross_cluster(self):
        inputs = dict(ROLE_INPUTS, LOCAL="false", SERVER_KUBECONFIG=str(self.server_kubeconfig),
                      SERVER_DOMAIN="b.remote", SERVER_PROMETHEUS_URL="https://user:secret@prom.b")
        result = self.run_sh(**inputs)
        self.assertEqual(result.rc, 0, result.output)
        self.assertEqual(self.argv(), [a for a in ROLE_ARGV if a != "--local=true"] + [
            "--server-kubeconfig=%s" % self.server_kubeconfig, "--server-domain=b.remote",
            "--server-prom=https://user:secret@prom.b"])
        self.assertIn("--server-prom=\\<redacted\\>", result.output)
        self.assertNotIn("secret", result.output)
        self.assertEqual([e for e in self.cluster_calls() if "label" in e["argv"]], [])
        server_debug = [e["argv"] for e in self.cluster_calls() if "--kubeconfig" in e["argv"]]
        self.assertEqual(len(server_debug), 3)
        self.assertTrue(all(a[:2] == ["--kubeconfig", str(self.server_kubeconfig)] for a in server_debug))
        self.assert_clean_end(result)

    def test_04_openshift_cross_cluster(self):
        result = self.run_sh(SERVER_KUBECONFIG=str(self.server_kubeconfig), SERVER_DOMAIN="b.remote")
        self.assertEqual(result.rc, 0, result.output)
        argv = self.argv()
        self.assertFalse([a for a in argv if a.startswith(("--all", "--local"))], argv)
        self.assertEqual(argv[-2:], ["--server-kubeconfig=%s" % self.server_kubeconfig, "--server-domain=b.remote"])
        self.assertEqual([e for e in self.cluster_calls() if "label" in e["argv"]], [])

    # -- 5-7: inputs ------------------------------------------------------------------------------------

    def test_05_rejected_combinations(self):
        kubeconfig = str(self.server_kubeconfig)
        cases = [
            ({"PLATFORM": "microshift", "LOCAL": "false"}, "PLATFORM=microshift requires LOCAL=true"),
            ({"SERVER_KUBECONFIG": kubeconfig, "LOCAL": "true"}, "cannot be combined with LOCAL=true"),
            ({"SERVER_KUBECONFIG": kubeconfig, "PLATFORM": "microshift", "LOCAL": "true"},
             "cannot be combined with LOCAL=true"),
            ({"SERVER_KUBECONFIG": kubeconfig, "EXTERNAL_SERVER_ADDRESS": "10.0.0.1"},
             "cannot be combined with EXTERNAL_SERVER_ADDRESS"),
            ({"SERVER_DOMAIN": "b.remote"}, "need SERVER_KUBECONFIG"),
            ({"SERVER_PROMETHEUS_URL": "https://prom.b"}, "need SERVER_KUBECONFIG"),
            ({"SERVER_KUBECONFIG": str(self.root / "missing")}, "is not a readable file"),
            ({"SERVER_KUBECONFIG": str(self.root)}, "is not a readable file"),
            ({"PLATFORM": "microshift", "METRICS": "true"}, "requires PROMETHEUS_URL"),
        ]
        for variables, message in cases:
            with self.subTest(variables=variables):
                (self.state / "log.jsonl").unlink(missing_ok=True)
                result = self.run_sh(**variables)
                self.assertEqual(result.rc, 1, result.output)
                self.assertIn(message, result.output)
                self.assertEqual(self.log(), [])

    def test_07_parent_environment(self):
        result = self.run_sh(PLATFORM="microshift", SERVER_KUBECONFIG=str(self.server_kubeconfig),
                             SERVER_DOMAIN="b.remote")
        self.assertEqual(result.rc, 0, result.output)
        self.assertNotIn("--local=true", self.argv())
        self.assertIn("--server-domain=b.remote", self.argv())
        for variable in ("SERVER_DOMAIN", "SERVER_PROMETHEUS_URL"):
            with self.subTest(exported=variable):
                (self.state / "log.jsonl").unlink(missing_ok=True)
                result = self.run_sh(**dict(ROLE_INPUTS, **{variable: "leftover"}))
                self.assertEqual(result.rc, 1, result.output)
                self.assertEqual(self.log(), [])

    # -- 8-10: labels -----------------------------------------------------------------------------------

    def test_08_labels_that_existed_before(self):
        self.set_nodes({"w1": {"netperf": "client"}, "w3": {"netperf": "server"}})
        before = self.netperf_labels()
        result = self.run_sh()
        self.assertEqual(result.rc, 0, result.output)
        self.assertIn("Node w1 already has netperf=client", result.output)
        self.assertIn("WARNING: other nodes carry a netperf label", result.output)
        self.assertIn("w3=server", result.output)
        self.assertEqual(self.netperf_labels(), before)
        writes = [e["argv"][:3] for e in self.cluster_calls() if e["argv"][:1] == ["label"]]
        self.assertEqual(writes, [["label", "nodes", "w2"], ["label", "nodes", "w2"]])

    def test_08_conflicting_label_stops_before_any_change(self):
        cases = {"client node": ({"w1": {"netperf": "server"}}, "node w1 has netperf=server but is chosen as the client"),
                 "server node": ({"w2": {"netperf": "client"}}, "node w2 has netperf=client but is chosen as the server")}
        for name, (labels, message) in cases.items():
            with self.subTest(name):
                (self.state / "log.jsonl").unlink(missing_ok=True)
                self.set_nodes(labels)
                before = self.netperf_labels()
                result = self.run_sh()
                self.assertEqual(result.rc, 1, result.output)
                self.assertIn(message, result.output)
                self.assertEqual(self.netperf_labels(), before)
                self.assertEqual(self.runs(), [])
                self.assertEqual([e for e in self.cluster_calls() if e["argv"][:1] == ["label"]], [])
                self.assert_clean_end(result)

    def test_09_inventory_failure_stops(self):
        self.behavior = {"fail": [{"tool": "kubectl", "match": ["get", "nodes", "-o", "jsonpath"]}]}
        result = self.run_sh()
        self.assertEqual(result.rc, 1, result.output)
        self.assertIn("could not read the node labels", result.output)
        self.assertEqual(self.runs(), [])
        self.assertEqual([e for e in self.cluster_calls() if e["argv"][:1] == ["label"]], [])
        self.assert_clean_end(result)

    def test_09_label_inserted_between_read_and_write(self):
        self.behavior = {"mutate": [{"tool": "kubectl", "match": ["label", "nodes", "w1", "netperf=client"],
                                     "node": "w1", "action": "set", "value": "client", "manager": "other"}]}
        result = self.run_sh()
        self.assertEqual(result.rc, 0, result.output)
        self.assertIn("Node w1 changed since it was read", result.output)
        self.assertIn("Node w1 already has netperf=client", result.output)
        self.assertEqual(self.netperf_labels(), {"w1": "client"})
        self.assertEqual(self.nodes()["w1"]["owners"]["netperf"], ["other"])

    def test_09_label_call_fails_without_answer(self):
        self.behavior = {"fail": [{"tool": "kubectl", "match": ["label", "nodes", "w2", "netperf=server"],
                                   "stderr": "Unable to connect to the server: net/http: TLS handshake timeout"}]}
        result = self.run_sh()
        self.assertEqual(result.rc, 1, result.output)
        self.assertIn("labeling w2 netperf=server did not succeed (exit code 1); its outcome is unknown", result.output)
        self.assertEqual(self.runs(), [])
        self.assertEqual(self.netperf_labels(), {})  # w1 was this run's and removed; w2 never written
        self.assert_clean_end(result)

    def test_09_label_taken_over_during_run(self):
        cases = {
            "value changed": {"action": "set", "value": "other", "manager": "someone"},
            "removed and re-added": {"action": "set", "value": "client", "manager": "someone"},
            "same-value apply": {"action": "co-own", "manager": "adopter"},
            "node recreated": {"action": "recreate"},
        }
        for name, mutation in cases.items():
            with self.subTest(name):
                self.set_nodes()
                (self.state / "used.json").unlink(missing_ok=True)
                self.behavior = {"mutate": [dict(mutation, tool="netperf", node="w1")]}
                result = self.run_sh()
                self.assertEqual(result.rc, 0, result.output)
                self.assertIn("WARNING: left netperf=client on node w1", result.output)
                self.assertIn("w1", self.netperf_labels())
                self.assertNotIn("w2", self.netperf_labels())

    def test_10_local_and_cross_cluster_leave_labels(self):
        cases = {"microshift same node": ROLE_INPUTS,
                 "cross-cluster": dict(ROLE_INPUTS, LOCAL="false", SERVER_KUBECONFIG=str(self.server_kubeconfig),
                                       SERVER_DOMAIN="b.remote")}
        for name, inputs in cases.items():
            with self.subTest(name):
                self.set_nodes({"w1": {"netperf": "client"}, "w2": {"netperf": "server"}})
                (self.state / "log.jsonl").unlink(missing_ok=True)
                result = self.run_sh(**inputs)
                self.assertEqual(result.rc, 0, result.output)
                self.assertEqual(self.netperf_labels(), {"w1": "client", "w2": "server"})
                self.assertEqual([e for e in self.cluster_calls() if "label" in e["argv"]], [])

    # -- 11-12: failed runs -----------------------------------------------------------------------------

    def test_11_failed_run_caller_cleans_up(self):
        for prow in ("", "1234"):
            for inputs in (ROLE_INPUTS, dict(ROLE_INPUTS, LOCAL="false", PLATFORM="openshift")):
                with self.subTest(prow=prow, local=inputs["LOCAL"]):
                    (self.state / "log.jsonl").unlink(missing_ok=True)
                    self.set_nodes()
                    self.behavior = {"netperf": {"exit": 3}}
                    result = self.run_sh(**dict(inputs, **(self.ci() if prow else {})))
                    self.assertEqual(result.rc, 3, result.output)
                    run_time = self.runs()[0]["t"]
                    self.assertEqual(self.cluster_calls(after=run_time), [])
                    self.assertIn("the caller owns cleanup", result.output)
                    self.assert_clean_end(result)

    def test_12_failed_run_with_cleanup(self):
        for prow in ("", "1234"):
            with self.subTest(prow=prow):
                (self.state / "log.jsonl").unlink(missing_ok=True)
                self.set_nodes()
                self.behavior = {"netperf": {"exit": 3}}
                result = self.run_sh(**(self.ci() if prow else {}))
                self.assertEqual(result.rc, 3, result.output)
                after = [e["argv"] for e in self.cluster_calls(after=self.runs()[0]["t"])]
                self.assertIn(["get", "pods", "-n", "netperf", "-o", "wide"], after)
                self.assertEqual(self.netperf_labels(), {})
                self.assertEqual(any("infrastructure" in a for a in after), prow != "")
                self.assert_clean_end(result)

    def test_23_binary_selection(self):
        with self.subTest("matching version is reused"):
            result = self.run_sh(NETPERF_VERSION="v0.1.43")
            self.assertEqual(result.rc, 0, result.output)
            self.assertIn("We already have the specified version available.", result.output)
            self.assertEqual([e for e in self.cluster_calls() if e["tool"] == "curl"], [])
        with self.subTest("non-default file name and URL, UUID unchanged"):
            (self.state / "log.jsonl").unlink(missing_ok=True)
            self.behavior = {}
            self.make_tarball("netperf-bin", "v2.0.0")
            result = self.run_sh(NETPERF_FILENAME="netperf-bin", NETPERF_VERSION="v2.0.0",
                                 NETPERF_URL="file:///builds/k8s-netperf.tar.gz", UUID="campaign_1/xc-a-to-b:02")
            self.assertEqual(result.rc, 0, result.output)
            download = [e for e in self.cluster_calls() if e["tool"] == "curl"][0]
            self.assertIn("file:///builds/k8s-netperf.tar.gz", download["argv"])
            run = self.runs()[0]
            self.assertEqual(run["version"], "v2.0.0")
            self.assertIn("--uuid=campaign_1/xc-a-to-b:02", run["argv"])
            self.assertTrue((self.workload / "netperf-bin").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
