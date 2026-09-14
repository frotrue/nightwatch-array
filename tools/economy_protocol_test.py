"""Verify the real Godot economy JSON-lines subprocess protocol."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    commands = [
        {"action": "state", "note": "한" * 800},  # Longer than Godot's old 1024-byte read.
        {"action": "next_round", "revision": 0},
        {"action": "buy", "id": "better_lens", "revision": 0},
        {"action": "buy", "id": "better_lens", "revision": 1},
    ]
    # Closing stdin tests EOF as well as several commands in one pipe read.
    result = subprocess.run(
        [args.godot, "--headless", "--path", str(root), "--script",
         "res://tools/economy_simulator.gd", "--", "--config", "tools/economy-external.json"],
        cwd=root, input="\n".join(map(json.dumps, commands)) + "\n",
        capture_output=True, text=True, encoding="utf-8", timeout=90,
    )
    log = result.stdout + result.stderr
    if result.returncode or "ERROR:" in log:
        raise RuntimeError(log)
    messages = [json.loads(line.removeprefix("SIM_JSON "))
                for line in result.stdout.splitlines() if line.startswith("SIM_JSON ")]
    responses = [message["payload"] for message in messages if message["kind"] == "result"]
    assert len(responses) == 3
    assert responses[0]["ok"] and responses[1]["error"] == "stale_revision" and responses[2]["ok"]
    assert messages[-1]["kind"] == "report"
    report = messages[-1]["payload"]
    assert report["base_research"] == 1 and len(report["rounds"]) == 1
    assert len(report["purchases"]) == 1 and abs(report["ledger_error"]) < 0.01
    initial = messages[0]["payload"]
    assert not any(node["id"] == "galactic_reference_frame" for node in initial["research"])
    def run(commands, *options):
        process = subprocess.run(
            [args.godot, "--headless", "--path", str(root), "--script",
             "res://tools/economy_simulator.gd", "--", *options],
            cwd=root, input="\n".join(map(json.dumps, commands)) + "\n",
            capture_output=True, text=True, encoding="utf-8", timeout=90,
        )
        if process.returncode or "ERROR:" in process.stdout + process.stderr:
            raise RuntimeError(process.stdout + process.stderr)
        return [json.loads(line.removeprefix("SIM_JSON "))
                for line in process.stdout.splitlines() if line.startswith("SIM_JSON ")]

    with tempfile.TemporaryDirectory(prefix="economy-checkpoints-", dir=root / "build") as folder:
        checkpoint = str(Path(folder) / "round-one.json")
        final_checkpoint = str(Path(folder) / "round-two.json")
        initial_commands = [
            {"action": "next_round", "revision": 0},
            {"action": "buy", "id": "better_lens", "revision": 1},
            {"action": "save", "path": checkpoint, "revision": 2},
            {"action": "next_round", "revision": 2},
        ]
        baseline = run(initial_commands, "--config", "tools/economy-external.json")
        baseline_report = baseline[-1]["payload"]
        assert Path(checkpoint).is_file()
        assert all(m["payload"]["ok"] for m in baseline if m["kind"] == "result")
        resumed = run([
            {"action": "next_round", "revision": 2},  # Loading must invalidate this old token.
            {"action": "next_round", "revision": 3},
        ], "--resume", checkpoint, "--checkpoint-out", final_checkpoint)
        replies = [m["payload"] for m in resumed if m["kind"] == "result"]
        assert replies[0]["ok"] and replies[1]["error"] == "stale_revision" and replies[2]["ok"]
        assert Path(final_checkpoint).is_file()
        for key in ("rounds", "purchases", "earned", "spent", "bank", "targets_seen", "targets_selected"):
            assert resumed[-1]["payload"][key] == baseline_report[key], key
        loaded = run([
            {"action": "load", "path": checkpoint, "revision": 0},
            {"action": "next_round", "revision": 3},
        ], "--config", "tools/economy-external.json")
        assert loaded[-1]["payload"]["rounds"] == baseline_report["rounds"]
        override = Path(folder) / "branch-config.json"
        override.write_text(json.dumps({"quality": 0.4}), encoding="utf-8")
        branch = run([], "--resume", checkpoint, "--resume-mode", "branch", "--config", str(override))
        assert branch[-1]["payload"]["config"]["quality"] == 0.4
        assert branch[-1]["payload"]["bank"] == report["bank"]
        assert branch[-1]["payload"]["checkpoint_lineage"][-1]["environment_changed"]
    print("ECONOMY_PROTOCOL_PASS: external decisions, stale revision, EOF, save/load, cross-process resume and branch config")


if __name__ == "__main__":
    main()
