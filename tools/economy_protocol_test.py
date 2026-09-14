"""Verify the real Godot economy JSON-lines subprocess protocol."""
import argparse
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    commands = [
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
    print("ECONOMY_PROTOCOL_PASS: external decisions, stale revision, no auto-buy, hidden-state filtering, EOF")


if __name__ == "__main__":
    main()
