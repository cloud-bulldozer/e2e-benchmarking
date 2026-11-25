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
GRACE = 10  # run.sh's fixed grace before SIGKILL for commands other than k8s-netperf

# One fake for every tool; the tool is the file name (anything else is k8s-netperf).
FAKE = r'''#!@PYTHON@ -I
import json, os, signal, subprocess, sys, time

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


def hang(rule):
    if rule.get("ignore_term"):
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
    if rule.get("child_holds_stdout"):
        child = subprocess.Popen([sys.executable, "-I", "-c",
                                  "import signal, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(3600)"])
        log(event="child", child=child.pid)
    log(event="hang")
    time.sleep(rule.get("seconds", 3600))
    log(event="hang-end")
    sys.exit(0)


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
        behavior = BEHAVIOR.get("version", "")
        log(event="version")
        if behavior == "hang":
            time.sleep(3600)
        if behavior != "empty":
            print("Version: %s\nGit Commit: fake" % VERSION)
        return
    config = BEHAVIOR.get("netperf", {})
    with open("result.csv", "w") as f:
        f.write("Driver,Scenario\nnetperf,TCP_STREAM\n")
    state = {"count": 0, "until": None, "code": 0}
    mode = config.get("mode", "default")

    def on_signal(sig, frame):
        name = signal.Signals(sig).name
        state["count"] += 1
        log(event="signal", sig=name)
        if mode == "pr301":
            if state["count"] == 1:
                state["until"] = time.monotonic() + config.get("cleanup", 1)
                state["code"] = 143 if sig == signal.SIGTERM else 130
            else:
                log(event="exit-without-cleanup")
                os._exit(state["code"])
        elif mode == "default":
            signal.signal(sig, signal.SIG_DFL)
            os.kill(os.getpid(), sig)

    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, on_signal)
    log(event="run", version=VERSION)
    apply_mutations()
    end = time.monotonic() + config.get("sleep", 0)
    while True:
        if state["until"] is not None and time.monotonic() >= state["until"]:
            log(event="cleanup-done")
            sys.exit(state["code"])
        if state["until"] is None and time.monotonic() >= end:
            break
        time.sleep(0.02)
    log(event="exit", code=config.get("exit", 0))
    sys.exit(config.get("exit", 0))


def curl():
    log(event="call")
    if "--retry-all-errors" in ARGS:
        rule = BEHAVIOR.get("download", {})
        if rule.get("stall"):
            hang({"ignore_term": rule.get("ignore_term")})
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
    index, rule = first("delay")
    if rule:
        time.sleep(rule["seconds"])
    index, rule = first("hang")
    if rule:
        hang(rule)
    index, rule = first("fail")
    if rule:
        sys.stderr.write(rule.get("stderr", "fake failure") + "\n")
        sys.exit(rule.get("exit", 1))
    cluster()


main()
'''

# Signals run.sh during bounded() at a chosen phase of a chosen command. use_hook() makes run.sh's test_hook()
# call it, in the test's copy of run.sh only.
HOOK = r'''#!@PYTHON@ -I
import json, os, signal, sys, time
config = json.load(open(os.path.join(os.environ["FAKE_STATE"], "hook.json")))
phase, command = sys.argv[1], " ".join(sys.argv[2:])
if not all(m in command for m in config["match"]):
    sys.exit(0)
with open(config["marker"] + ".phases", "a") as f:
    f.write(phase + "\n")
if phase != config["phase"] or os.path.exists(config["marker"]):
    sys.exit(0)
open(config["marker"], "w").close()
deadline = time.monotonic() + 20
while time.monotonic() < deadline:
    with open(config["log"]) as f:
        if any('"event": "run"' in line for line in f):
            break
    time.sleep(0.02)
os.kill(os.getppid(), signal.SIGTERM)
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
        self.hook = self.bin / "hook"
        self.hook.write_text(HOOK.replace("@PYTHON@", sys.executable))
        self.hook.chmod(0o755)
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
            "UUID": "test-uuid", "TEST_TIMEOUT": "60", "CALL_TIMEOUT": "2", "DOWNLOAD_TIMEOUT": "5",
            "INDEX_TIMEOUT": "20", "TEST_KILL_AFTER": "2",
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

    def signals(self):
        return [e["sig"] for e in self.log() if e.get("event") == "signal"]

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

    def wait_for(self, predicate, timeout=20):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.02)
        self.fail("condition not reached within %ss" % timeout)

    def assert_clean_end(self, result):
        self.assertEqual(result.leftovers, [], "processes left in run.sh's session")
        self.assertEqual(list(self.tmp.iterdir()), [], "files left in TMPDIR")

    def ci(self):
        """CI variables that make utils/index.sh index; its fixed /tmp paths get unique names and are removed."""
        name = "e2e-netperf-test-%s" % uuid.uuid4().hex[:12]
        self.addCleanup(shutil.rmtree, "/tmp/" + name, True)
        self.addCleanup(Path("/tmp/%s-uuid.txt" % name).unlink, True)
        return {"PROW_JOB_ID": "1234", "JOB_NAME": "job", "BUILD_ID": "7", "UUID": name, "WORKLOAD_NAME": name}

    def use_hook(self, phase, match=("k8s-netperf", "--uuid=")):
        """Make the copy of run.sh call the hook script at its test points."""
        config = {"phase": phase, "match": list(match), "marker": str(self.state / "hook-fired"),
                  "log": str(self.state / "log.jsonl")}
        (self.state / "hook.json").write_text(json.dumps(config))
        (self.state / "hook-fired").unlink(missing_ok=True)
        (self.state / "hook-fired.phases").unlink(missing_ok=True)
        script = self.workload / "run.sh"
        text = script.read_text()
        no_op = "test_hook() {\n  :\n}\n"
        hooked = 'test_hook() {\n  "%s" "$@" || true\n}\n' % self.hook
        if hooked not in text:
            self.assertEqual(text.count(no_op), 1, "run.sh has no test_hook() to replace")
            script.write_text(text.replace(no_op, hooked))

    # -- 1-4: command line in each mode -------------------------------------------------------------

    def test_01_openshift_default(self):
        result = self.run_sh()
        self.assertEqual(result.rc, 0, result.output)
        self.assertEqual(self.argv(), ["--all=true"] + DEFAULT_ARGV)
        self.assertIn("Executing command: timeout --foreground -k 2 60 ./k8s-netperf --all=true", result.output)
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
            ({"TEST_TIMEOUT": "0"}, "TEST_TIMEOUT=0 is not a duration"),
            ({"DOWNLOAD_TIMEOUT": "never"}, "DOWNLOAD_TIMEOUT=never is not a duration"),
            ({"INDEX_TIMEOUT": "-5"}, "INDEX_TIMEOUT=-5 is not a duration"),
            ({"TEST_KILL_AFTER": "inf"}, "TEST_KILL_AFTER=inf is not a duration"),
        ]
        for variables, message in cases:
            with self.subTest(variables=variables):
                (self.state / "log.jsonl").unlink(missing_ok=True)
                result = self.run_sh(**variables)
                self.assertEqual(result.rc, 1, result.output)
                self.assertIn(message, result.output)
                self.assertEqual(self.log(), [])

    def test_06_durations(self):
        for value in ("14400", "4h", ".5s", "1e3s", "1e-7s", "0x1p4", "0x0d", "0x1d", "1.5m", "1d", " 5"):
            with self.subTest(accepted=value):
                (self.state / "log.jsonl").unlink(missing_ok=True)
                result = self.run_sh(TEST_KILL_AFTER=value)
                self.assertEqual(result.rc, 0, result.output)
                self.assertEqual(len(self.runs()), 1)
        for value in ("0", "0s", "0x0", "-1", "inf", "nan", "abc", "5x", "'1", "1,5", "1ss"):
            with self.subTest(rejected=value):
                (self.state / "log.jsonl").unlink(missing_ok=True)
                result = self.run_sh(TEST_KILL_AFTER=value, LC_ALL="C")
                self.assertEqual(result.rc, 1, result.output)
                self.assertIn("is not a duration", result.output)
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
        for kind in ("fail", "hang"):
            with self.subTest(kind=kind):
                (self.state / "log.jsonl").unlink(missing_ok=True)
                self.behavior = {kind: [{"tool": "kubectl", "match": ["get", "nodes", "-o", "jsonpath"]}]}
                result = self.run_sh()
                self.assertEqual(result.rc, 1, result.output)
                self.assertIn("could not read the node labels", result.output)
                self.assertEqual(self.runs(), [])
                self.assertEqual([e for e in self.cluster_calls() if e["argv"][:1] == ["label"]], [])
                self.assertLess(result.elapsed, 2 * (2 + GRACE) + 10)
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

    def test_09_label_call_times_out(self):
        self.behavior = {"hang": [{"tool": "kubectl", "match": ["label", "nodes", "w2", "netperf=server"]}]}
        result = self.run_sh()
        self.assertEqual(result.rc, 1, result.output)
        self.assertIn("labeling w2 netperf=server did not succeed (exit code 124); its outcome is unknown", result.output)
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

    # -- 11-16: failed runs and deadlines ---------------------------------------------------------------

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

    def test_13_stalled_download(self):
        for ignore_term in (False, True):
            with self.subTest(ignore_term=ignore_term):
                (self.state / "log.jsonl").unlink(missing_ok=True)
                (self.workload / "k8s-netperf").unlink(missing_ok=True)
                self.behavior = {"download": {"stall": True, "ignore_term": ignore_term}}
                result = self.run_sh(DOWNLOAD_TIMEOUT="2")
                self.assertEqual(result.rc, 124, result.output)
                self.assertLess(result.elapsed, 2 + GRACE + 5)
                self.assertIn("exceeded DOWNLOAD_TIMEOUT=2", result.output)
                self.assertEqual([e["tool"] for e in self.log() if e.get("event") == "call"], ["curl"])
                self.assertEqual(self.runs(), [])
                self.assert_clean_end(result)

    def test_14_api_call_hangs_after_benchmark(self):
        self.behavior = {"hang": [{"tool": "oc", "match": ["get", "pods"]}]}
        result = self.run_sh()
        self.assertEqual(result.rc, 0, result.output)
        c, n, i = 2 + GRACE, 60 + 2, 20 + GRACE
        self.assertLess(result.elapsed, 21 * c + n + i + 30)
        self.assertLess(result.elapsed, 2 + 2 + 15)  # one hung call: CALL_TIMEOUT, no grace needed
        self.assert_clean_end(result)

    def test_15_index_call_hangs(self):
        cases = {"ignores TERM": {"ignore_term": True},
                 "child holds stdout": {"child_holds_stdout": True}}
        for name, rule in cases.items():
            with self.subTest(name):
                (self.state / "log.jsonl").unlink(missing_ok=True)
                self.set_nodes()
                self.behavior = {"hang": [dict(rule, tool="oc", match=["get", "infrastructure", "infrastructureName"])]}
                result = self.run_sh(INDEX_TIMEOUT="60", **self.ci())
                self.assertEqual(result.rc, 0, result.output)
                calls = self.cluster_calls()
                hung = [k for k, e in enumerate(calls) if "infrastructureName" in " ".join(e["argv"])][0]
                self.assertGreater(len(calls), hung + 1, "index.sh did not continue after the hung call")
                self.assertLess(calls[hung + 1]["t"] - calls[hung]["t"], 2 + GRACE + 3)
                self.assert_clean_end(result)

    def test_15_index_interrupted_leaves_no_files(self):
        hang = {"hang": [{"tool": "oc", "match": ["infrastructureName"], "ignore_term": True,
                          "child_holds_stdout": True}]}
        with self.subTest("INDEX_TIMEOUT"):
            self.behavior = hang
            result = self.run_sh(CALL_TIMEOUT="30", INDEX_TIMEOUT="2", **self.ci())
            self.assertEqual(result.rc, 0, result.output)
            self.assertLess(result.elapsed, 2 + GRACE + 10)
            self.assert_clean_end(result)
        with self.subTest("TERM during indexing"):
            (self.state / "log.jsonl").unlink(missing_ok=True)
            self.set_nodes()
            self.behavior = hang
            process = self.start(CALL_TIMEOUT="30", INDEX_TIMEOUT="60", **self.ci())
            self.wait_for(lambda: [e for e in self.log() if e.get("event") == "hang"])
            os.kill(process.pid, signal.SIGTERM)
            result = self.finish(process)
            self.assertEqual(result.rc, 143, result.output)
            self.assertLess(result.elapsed, 30)
            self.assert_clean_end(result)

    def test_16_slow_preparation_then_failure(self):
        self.behavior = {"delay": [{"tool": "kubectl", "match": ["get", "nodes"], "seconds": 1.5}],
                         "netperf": {"exit": 5}}
        result = self.run_sh(CLEAN_UP="false", TEST_TIMEOUT="5")
        self.assertEqual(result.rc, 5, result.output)
        c, d, n = 2 + GRACE, 5 + GRACE, 5 + 2
        self.assertLess(result.elapsed, 9 * c + d + n + 30)
        self.assertEqual(self.cluster_calls(after=self.runs()[0]["t"]), [])

    # -- 17-22: signals ----------------------------------------------------------------------------------

    def test_17_benchmark_ignores_first_term(self):
        self.behavior = {"netperf": {"mode": "ignore", "sleep": 60}}
        result = self.run_sh(TEST_TIMEOUT="2", TEST_KILL_AFTER="2")
        self.assertEqual(result.rc, 137, result.output)
        self.assertEqual(self.signals(), ["SIGTERM"])
        self.assertLess(result.elapsed, 2 + 2 + 15)
        self.assert_clean_end(result)

    def test_18_pr301_cleanup_at_timeout(self):
        self.behavior = {"netperf": {"mode": "pr301", "sleep": 60, "cleanup": 1}}
        result = self.run_sh(TEST_TIMEOUT="2", TEST_KILL_AFTER="5")
        self.assertEqual(result.rc, 124, result.output)
        self.assertEqual(self.signals(), ["SIGTERM"])
        self.assertTrue([e for e in self.log() if e.get("event") == "cleanup-done"])
        self.assert_clean_end(result)

    def test_19_signal_to_run_sh(self):
        cases = [("TERM", signal.SIGTERM, False, 143), ("INT", signal.SIGINT, False, 130),
                 ("HUP", signal.SIGHUP, False, 129), ("TERM to the process group", signal.SIGTERM, True, 143)]
        for name, sig, group, code in cases:
            with self.subTest(name):
                (self.state / "log.jsonl").unlink(missing_ok=True)
                self.set_nodes()
                self.behavior = {"netperf": {"mode": "pr301", "sleep": 60, "cleanup": 1}}
                process = self.start(TEST_TIMEOUT="300", TEST_KILL_AFTER="30")
                self.wait_for(lambda: self.runs())
                sent = time.time()
                (os.killpg if group else os.kill)(process.pid, sig)
                result = self.finish(process)
                self.assertEqual(result.rc, code, result.output)
                self.assertEqual(self.signals(), ["SIGTERM"])
                done = [e for e in self.log() if e.get("event") == "cleanup-done"]
                self.assertEqual(len(done), 1)
                self.assertLess(result.elapsed, 20)
                self.assertEqual(self.cluster_calls(after=sent), [])
                self.assertIn("Stopped by SIG%s" % signal.Signals(sig).name[3:], result.output)
                self.assert_clean_end(result)

    def test_20_second_signal_skips_cleanup(self):
        self.behavior = {"netperf": {"mode": "pr301", "sleep": 60, "cleanup": 30}}
        process = self.start(TEST_TIMEOUT="300", TEST_KILL_AFTER="60")
        self.wait_for(lambda: self.runs())
        os.kill(process.pid, signal.SIGTERM)
        self.wait_for(lambda: self.signals())
        time.sleep(0.3)
        os.kill(process.pid, signal.SIGTERM)
        result = self.finish(process)
        self.assertEqual(result.rc, 143, result.output)
        self.assertEqual(self.signals(), ["SIGTERM", "SIGTERM"])
        self.assertTrue([e for e in self.log() if e.get("event") == "exit-without-cleanup"])
        self.assertLess(result.elapsed, 15)
        self.assert_clean_end(result)

    def test_21_signal_windows(self):
        for phase in ("launched", "registered"):
            with self.subTest(phase=phase):
                (self.state / "log.jsonl").unlink(missing_ok=True)
                (self.state / "hook-fired").unlink(missing_ok=True)
                self.set_nodes()
                self.behavior = {"netperf": {"mode": "pr301", "sleep": 300, "cleanup": 1}}
                self.use_hook(phase)
                result = self.run_sh(TEST_TIMEOUT="300", TEST_KILL_AFTER="60")
                self.assertEqual(result.rc, 143, result.output)
                self.assertEqual(self.signals(), ["SIGTERM"])
                self.assertEqual(len([e for e in self.log() if e.get("event") == "cleanup-done"]), 1)
                self.assertLess(result.elapsed, 20)
                self.assert_clean_end(result)
        with self.subTest(phase="rewait"):
            (self.state / "log.jsonl").unlink(missing_ok=True)
            (self.state / "hook-fired").unlink(missing_ok=True)
            self.behavior = {"netperf": {"mode": "pr301", "sleep": 300, "cleanup": 120}}
            self.use_hook("rewait")
            process = self.start(TEST_TIMEOUT="300", TEST_KILL_AFTER="200")
            phases = self.state / "hook-fired.phases"
            self.wait_for(lambda: phases.exists() and "registered" in phases.read_text())
            time.sleep(0.5)  # run.sh is now blocked in wait: the next TERM makes the wait loop iterate
            os.kill(process.pid, signal.SIGTERM)
            result = self.finish(process)
            self.assertEqual(result.rc, 143, result.output)
            self.assertEqual(self.signals(), ["SIGTERM", "SIGTERM"])
            self.assertTrue([e for e in self.log() if e.get("event") == "exit-without-cleanup"])
            self.assertLess(result.elapsed, 20)
            self.assert_clean_end(result)
        with self.subTest(phase="before k8s-netperf"):
            (self.state / "log.jsonl").unlink(missing_ok=True)
            self.behavior = {"hang": [{"tool": "oc", "match": ["label", "nodes", "-l"]}]}
            process = self.start(LOCAL="true", CALL_TIMEOUT="300")
            self.wait_for(lambda: [e for e in self.log() if e.get("event") == "hang"])
            os.kill(process.pid, signal.SIGTERM)
            result = self.finish(process)
            self.assertEqual(result.rc, 143, result.output)
            self.assertEqual(self.runs(), [])
            self.assertLess(result.elapsed, GRACE + 5)
            self.assert_clean_end(result)

    def test_22_abrupt_end_of_run_sh(self):
        cases = {
            "during k8s-netperf": ({"netperf": {"mode": "ignore", "sleep": 300}}, {}, lambda: self.runs()),
            "during the download": ({"download": {"stall": True, "ignore_term": True}}, {"DOWNLOAD_TIMEOUT": "2"},
                                    lambda: [e for e in self.log() if e.get("event") == "hang"]),
            "during index.sh": ({"hang": [{"tool": "oc", "match": ["infrastructureName"], "ignore_term": True,
                                           "child_holds_stdout": True}]},
                                self.ci(),
                                lambda: [e for e in self.log() if e.get("event") == "hang"]),
        }
        for name, (behavior, variables, started) in cases.items():
            with self.subTest(name):
                (self.state / "log.jsonl").unlink(missing_ok=True)
                self.set_nodes()
                if name == "during the download":
                    (self.workload / "k8s-netperf").unlink(missing_ok=True)
                else:
                    self.write_fake(self.workload / "k8s-netperf", "v0.1.43")
                self.behavior = behavior
                process = self.start(**variables)
                self.wait_for(started)
                os.kill(process.pid, signal.SIGKILL)
                process.process.wait(timeout=10)
                time.sleep(3)  # past DOWNLOAD_TIMEOUT / CALL_TIMEOUT: only run.sh's group KILL would end these
                members = session_members(process.pid)
                self.assertTrue(members, "nothing left in the session: the test did not exercise survivors")
                logged = {e["pid"]: e["sid"] for e in self.log()}
                for pid in members:
                    if pid in logged:
                        self.assertEqual(logged[pid], process.pid)
                self.kill_session(process.pid)
                self.wait_for(lambda: not session_members(process.pid), timeout=5)

    def test_23_binary_selection(self):
        with self.subTest("matching version is reused"):
            result = self.run_sh(NETPERF_VERSION="v0.1.43")
            self.assertEqual(result.rc, 0, result.output)
            self.assertIn("We already have the specified version available.", result.output)
            self.assertEqual([e for e in self.cluster_calls() if e["tool"] == "curl"], [])
        for behavior in ("hang", "empty"):
            with self.subTest(version_probe=behavior):
                (self.state / "log.jsonl").unlink(missing_ok=True)
                self.write_fake(self.workload / "k8s-netperf", "v0.1.43")
                self.behavior = {"version": behavior}
                result = self.run_sh(NETPERF_VERSION="v0.1.43")
                self.assertEqual(result.rc, 0, result.output)
                self.assertIn("Switching k8s-netperf version.", result.output)
                self.assertEqual(self.runs()[0]["version"], "v9.9.9-downloaded")
                self.assertLess(result.elapsed, 30)
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
