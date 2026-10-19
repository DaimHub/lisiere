#!/usr/bin/env python3
"""Profile rendered interactions in an isolated Release. Never open the personal browser container."""
import argparse
from datetime import datetime
import importlib.util
import json
from pathlib import Path
import signal
import subprocess
import threading
import time
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location("release_validation", Path(__file__).with_name("validate-release.py"))
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


def wait_for(condition, seconds, label):
    deadline = time.monotonic() + seconds
    while not condition():
        if time.monotonic() > deadline:
            raise RuntimeError(f"Timed out: {label}")
        time.sleep(0.1)


def export(output, pid, phases, time_profiler=False):
    trace = output / "motion.trace"
    toc_path = output / "toc.xml"
    subprocess.run(["xcrun", "xctrace", "export", "--input", str(trace), "--toc", "--output", str(toc_path)], check=True)
    toc = ET.parse(toc_path)
    for parent in toc.iter():
        for child in list(parent):
            if child.tag == "environment":
                parent.remove(child)
    toc.write(toc_path, encoding="unicode")
    origin = datetime.fromisoformat(toc.findtext(".//summary/start-date")).timestamp()
    duration = float(toc.findtext(".//summary/duration"))
    for table in ["hitches"] + (["time-profile"] if time_profiler else []):
        subprocess.run(["xcrun", "xctrace", "export", "--input", str(trace), "--xpath",
                        f'/trace-toc/run[@number="1"]/data/table[@schema="{table}"]',
                        "--output", str(output / f"{table}.xml")], check=True)
    results = summarize(ET.parse(output / "hitches.xml"), pid, origin, duration, phases)
    control = next(item for item in results if item["name"] == "detector-control")
    report = {"pid": pid, "recording_seconds": duration,
              "instruments": ["Hitches"] + (["Time Profiler"] if time_profiler else []),
              "detector_verified": control["max_hitch_ms"] >= 50, "scenarios": results,
              "limitations": "Short local samples under Instruments. Hitches are delayed presentation, not FPS. No physical gesture or Chrome comparison."}
    (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    if not report["detector_verified"]:
        raise RuntimeError("Positive control missed the deliberate 100 ms stalls. Capture cannot validate smoothness.")
    for item in results:
        print(f"{item['name']}: {item['hitches']} hitches, max {item['max_hitch_ms']:.2f} ms, total {item['total_hitch_ms']:.2f} ms", flush=True)


def summarize(xml, pid, origin, duration, phases):
    """Decode Instruments references and attribute only this process's in-range presentation delays."""
    refs = {node.attrib["id"]: node for node in xml.iter() if "id" in node.attrib}
    def resolve(node):
        return refs[node.attrib["ref"]] if "ref" in node.attrib else node
    events = []
    for row in xml.findall(".//row"):
        start, delay, process = [resolve(node) for node in list(row)[:3]]
        process_pid = process.find("pid")
        if process_pid is None or int(resolve(process_pid).text) != pid:
            continue
        relative = int(start.text) / 1e9
        if 0 <= relative <= duration:
            events.append((origin + relative, int(delay.text) / 1e6))
    results = []
    for phase in phases:
        start, end = phase["start_epoch"], phase["end_epoch"]
        if end <= start or start < origin or end > origin + duration:
            raise RuntimeError(f"Scenario outside recording: {phase['name']}")
        if phase.get("window_active") is False:
            raise RuntimeError(f"QA window lost focus: {phase['name']}")
        delays = [delay for timestamp, delay in events if start <= timestamp < end]
        results.append({**phase, "hitches": len(delays), "total_hitch_ms": sum(delays),
                        "max_hitch_ms": max(delays, default=0),
                        "hitch_ms_per_second": sum(delays) / (end - start),
                        "over_25_ms": sum(delay > 25.1 for delay in delays)})
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--time-profiler", action="store_true", help="Add CPU stack sampling for diagnosis; use the same instruments for before/after comparisons")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    app, qa_id = validation.prepare(args.app.resolve(), output)
    server = validation.ThreadingHTTPServer(("127.0.0.1", 0), validation.Fixture)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    root = Path.home() / "Library/Containers" / qa_id / "Data/Library/Application Support" / qa_id / "Validation"
    recorder = None
    try:
        with (output / "app.log").open("w") as log:
            launch = subprocess.Popen(["open", "-W", "-a", str(app), "--stdout", str(output / "app.log"),
                                       "--stderr", str(output / "app.log"), "--env", "LISIERE_QA_VALIDATION=motion",
                                       "--env", f"LISIERE_QA_BASE_URL=http://127.0.0.1:{server.server_port}"], stdout=log, stderr=log)
            wait_for(lambda: (root / "motion-ready.json").exists(), 45, "QA ready")
            ready = json.loads((root / "motion-ready.json").read_text())
            (output / "ready.json").write_text(json.dumps(ready, indent=2) + "\n")
            print(f"QA ready: {ready}", flush=True)
            with (output / "record.log").open("w") as record_log:
                # The full Animation Hitches template includes very expensive Frame Lifetimes data.
                sampling = ["--instrument", "Time Profiler"] if args.time_profiler else []
                recorder = subprocess.Popen(["xcrun", "xctrace", "record", "--template", "Blank", "--instrument", "Hitches",
                                             *sampling, "--attach", str(ready["pid"]), "--time-limit", "45s",
                                             "--output", str(output / "motion.trace"), "--no-prompt"], stdout=record_log, stderr=record_log)
                wait_for(lambda: "Starting recording" in (output / "record.log").read_text(), 30, "recorder start")
                # Let attachment finish before beginning the first measured interval.
                time.sleep(2)
                (root / "motion-go").touch()
                wait_for(lambda: (root / "motion-phases.json").exists(), 40, "rendered scenarios")
                recorder.send_signal(signal.SIGINT)
                print("Scenarios complete; processing trace", flush=True)
                recorder.wait(timeout=120)
                if recorder.returncode:
                    raise RuntimeError("Instruments capture failed; inspect record.log")
            (root / "motion-stop").touch()
            launch.wait(timeout=15)
        data = json.loads((root / "motion-phases.json").read_text())
        (output / "phases.json").write_text(json.dumps(data, indent=2) + "\n")
        export(output, ready["pid"], data["phases"], args.time_profiler)
    finally:
        if recorder is not None and recorder.poll() is None:
            recorder.terminate()
            try:
                recorder.wait(timeout=10)
            except subprocess.TimeoutExpired:
                recorder.kill()
                recorder.wait()
        validation.stop_qa(app)
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
