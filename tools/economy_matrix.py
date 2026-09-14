"""Run sequential seeded economy probes, retaining exact configs/reports/logs."""
import argparse
import csv
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--seeds", default="42,43,44")
    parser.add_argument("--strategies", default="cheapest,income_first,random")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timeout", type=float, default=900)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    base = json.loads(args.config.read_text(encoding="utf-8")) if args.config else {}
    seeds = [int(value) for value in args.seeds.split(",")]
    strategies = args.strategies.split(",")
    if any(value not in ("cheapest", "income_first", "random", "priority") for value in strategies):
        parser.error("Matrix strategies must be automatic")
    args.output.mkdir(parents=True, exist_ok=False)
    rows = []
    for strategy in strategies:
        for seed in seeds:
            name = f"{strategy}-{seed}"
            config = base | {"seed": seed, "strategy": strategy}
            config_path = (args.output / f"{name}.config.json").resolve()
            report_path = (args.output / f"{name}.report.json").resolve()
            config_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
            with (args.output / f"{name}.log").open("w", encoding="utf-8") as log:
                completed = subprocess.run(
                    [args.godot, "--headless", "--path", str(root), "--script",
                     "res://tools/economy_simulator.gd", "--", "--config", str(config_path),
                     "--output", str(report_path)],
                    cwd=root, stdout=log, stderr=subprocess.STDOUT, timeout=args.timeout,
                )
            text = (args.output / f"{name}.log").read_text(encoding="utf-8")
            if completed.returncode or "SCRIPT ERROR:" in text or "ERROR:" in text:
                raise RuntimeError(f"{name} failed; inspect its log")
            report = json.loads(report_path.read_text(encoding="utf-8"))
            row = {"strategy": strategy, "seed": seed, "rounds": len(report["rounds"])}
            for key in ("stop_reason", "active_seconds", "base_research", "extension_research",
                        "maximum_purchase_batch", "longest_no_purchase_rounds", "bank", "ledger_error"):
                row[key] = report[key]
            rows.append(row)
            with (args.output / "summary.csv").open("w", newline="", encoding="utf-8") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(row))
                writer.writeheader()
                writer.writerows(rows)
            print(json.dumps(row), flush=True)


if __name__ == "__main__":
    main()
