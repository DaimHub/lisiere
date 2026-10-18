#!/usr/bin/env python3
"""Run the shipping Release in an isolated, re-signed QA copy. Never launch the personal bundle."""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import threading
import time
import uuid


class Fixture(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        path = self.path.split("?", 1)[0].lstrip("/")
        if path == "disconnect":
            self.connection.close()
            return
        if path == "slow":
            time.sleep(2)
        if path == "redirect":
            self.send_response(302)
            self.send_header("Location", "/two")
            self.end_headers()
            return
        if path == "download":
            body = b"Lisiere QA download\n"
        elif path == "blocking":
            body = (f'<!doctype html><title>QA blocking</title><h1>Local blocking fixture</h1>'
                    '<script>window.trackerResult="pending";</script>'
                    f'<script src="http://localhost:{self.server.server_port}/qa-tracker" '
                    'onload="window.trackerResult=\'loaded\'" onerror="window.trackerResult=\'blocked\'"></script>').encode()
        elif path == "qa-tracker":
            body = b"window.localTrackerExecuted = true;"
        else:
            body = (f'<!doctype html><meta charset="utf-8"><title>QA {path}</title>'
                    f'<h1>Release validation: {path}</h1>'
                    '<form action="/submitted"><input name="value" aria-label="Fixture value">'
                    '<button>Submit</button></form><a href="/two">Next page</a>').encode()
        self.send_response(200)
        mime = "application/octet-stream" if path == "download" else "text/javascript" if path == "qa-tracker" else "text/html"
        self.send_header("Content-Type", mime)
        if path == "download":
            self.send_header("Content-Disposition", 'attachment; filename="qa.txt"')
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def performance_result(metrics):
    budgets = json.loads(Path(__file__).with_name("performance-budgets.json").read_text())
    values = dict(metrics)
    values["resident_growth_bytes"] = metrics["resident_3_bytes"] - metrics["resident_0_bytes"]
    results = {key: {"actual": values[key], "maximum": maximum, "passed": 0 <= values[key] <= maximum}
               for key, maximum in budgets.items()}
    # Shrinking RSS is healthy. Individual samples must still be valid measurements.
    results["resident_growth_bytes"]["passed"] = (min(metrics[f"resident_{i}_bytes"] for i in range(4)) > 0
                                                  and values["resident_growth_bytes"] <= budgets["resident_growth_bytes"])
    return results


def stop_qa(app):
    """Timeout cleanup targets only this unique, agent-created bundle's executable."""
    executable = str(app / "Contents/MacOS/Lisiere")
    result = subprocess.run(["pgrep", "-f", "^" + re.escape(executable) + "($| )"], capture_output=True, text=True)
    for value in result.stdout.split():
        pid = int(value)
        command = subprocess.run(["ps", "-p", str(pid), "-o", "args="], capture_output=True, text=True).stdout.strip()
        if command == executable or command.startswith(executable + " "):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def prepare(app: Path, output: Path):
    run("codesign", "--verify", "--deep", "--strict", str(app))
    identity = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if identity["CFBundleIdentifier"] != "io.github.daimhub.lisiere":
        raise RuntimeError("Expected the production Lisière Release as input")
    signed = run("codesign", "-d", "--entitlements", ":-", str(app), capture_output=True).stdout
    entitlements = plistlib.loads(signed)
    if not entitlements.get("com.apple.security.app-sandbox") or entitlements.get("com.apple.security.get-task-allow"):
        raise RuntimeError("Input must be sandboxed and must not permit debugger injection")
    details = run("codesign", "-dv", str(app), capture_output=True).stderr.decode()
    if "runtime" not in details:
        raise RuntimeError("Input must retain hardened runtime")
    qa_id = "io.github.daimhub.lisiere.qa." + uuid.uuid4().hex
    copy = output / "Lisiere QA.app"
    if copy.exists():
        raise RuntimeError("Use a fresh output directory; an earlier QA bundle will not be overwritten")
    run("ditto", str(app), str(copy))
    identity["CFBundleIdentifier"] = qa_id
    identity["CFBundleName"] = identity["CFBundleDisplayName"] = "Lisière QA"
    # This copy must never register itself as an alternative default browser or update client.
    identity.pop("CFBundleURLTypes", None)
    identity.pop("CFBundleDocumentTypes", None)
    identity.pop("SUPublicEDKey", None)
    identity["SUEnableAutomaticChecks"] = False
    (copy / "Contents/Info.plist").write_bytes(plistlib.dumps(identity))
    # Provisioned identity and passkeys cannot transfer to a new ad hoc QA identity.
    # Their real distribution validation remains a separate gate; never alter the input app.
    omitted = []
    for key in ["com.apple.developer.web-browser.public-key-credential", "com.apple.application-identifier",
                "com.apple.developer.team-identifier", "keychain-access-groups"]:
        if key in entitlements:
            omitted.append(key)
            entitlements.pop(key)
    (copy / "Contents/embedded.provisionprofile").unlink(missing_ok=True)
    entitlements["com.apple.security.cs.disable-library-validation"] = True
    entitlements["com.apple.security.temporary-exception.mach-lookup.global-name"] = [qa_id + "-spks", qa_id + "-spki"]
    entitlement_path = output / "qa-entitlements.plist"
    entitlement_path.write_bytes(plistlib.dumps(entitlements))
    run("codesign", "--force", "--sign", "-", "--options", "runtime", "--entitlements", str(entitlement_path), str(copy))
    run("codesign", "--verify", "--deep", "--strict", str(copy))
    binary = app / "Contents/MacOS/Lisiere"
    # codesign changes the embedded signature, so compare executable code UUIDs instead of whole signed bytes.
    source_uuid = run("dwarfdump", "--uuid", str(binary), capture_output=True).stdout.decode().split("(")[0].strip()
    qa_uuid = run("dwarfdump", "--uuid", str(copy / "Contents/MacOS/Lisiere"), capture_output=True).stdout.decode().split("(")[0].strip()
    if source_uuid != qa_uuid:
        raise RuntimeError("QA executable identity differs from source Release")
    provenance = {"source": str(app), "source_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                  "executable_uuid": source_uuid, "qa_bundle": str(copy), "qa_id": qa_id,
                  "toolchain": run("xcodebuild", "-version", capture_output=True).stdout.decode(),
                  "commit": run("git", "rev-parse", "HEAD", capture_output=True).stdout.decode().strip(),
                  "dirty": bool(run("git", "status", "--porcelain", capture_output=True).stdout),
                  "protections": {"sandbox": True, "hardened_runtime": True, "get_task_allow": False},
                  "provisioned_entitlements_omitted_in_qa": omitted,
                  "note": "Local ad hoc QA copy. Developer ID/notarization/Sparkle delivery are separate gates."}
    (output / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    return copy, qa_id


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--prepare-only", action="store_true", help="Create an isolated copy for manual native inspection")
    parser.add_argument("--reduce-motion", action="store_true", help="Override only the QA window's accessibility environment")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    app, qa_id = prepare(args.app.resolve(), args.output.resolve())
    if args.prepare_only:
        print(app)
        return
    server = ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    root = Path.home() / "Library/Containers" / qa_id / "Data/Library/Application Support" / qa_id / "Validation"
    try:
        for phase in ["journey", "restore"]:
            start = time.monotonic()
            with (args.output / f"{phase}.log").open("w") as log:
                # Launch without positional arguments: AppKit can treat them as document requests
                # and suppress SwiftUI's first untitled window. QA receives its inputs in the environment.
                command = ["open", "-W", "--stdout", str((args.output / f"{phase}.log").resolve()),
                           "--stderr", str((args.output / f"{phase}.log").resolve()), "-a", str(app), "--env", f"LISIERE_QA_VALIDATION={phase}",
                           "--env", f"LISIERE_QA_BASE_URL=http://127.0.0.1:{server.server_port}"]
                if args.reduce_motion:
                    command.extend(["--env", "LISIERE_QA_REDUCE_MOTION=1"])
                process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
                try:
                    code = process.wait(timeout=180)
                except subprocess.TimeoutExpired:
                    stop_qa(app)
                    process.kill()
                    process.wait()
                    raise RuntimeError(f"{phase}: timed out; see retained log")
                except BaseException:
                    stop_qa(app)
                    if process.poll() is None:
                        process.kill()
                    process.wait()
                    raise
            report_path = root / f"{phase}.json"
            if not report_path.exists():
                raise RuntimeError(f"{phase}: missing report (exit {code}); see retained log")
            report = json.loads(report_path.read_text())
            report["process_seconds"] = time.monotonic() - start
            (args.output / f"{phase}.json").write_text(json.dumps(report, indent=2) + "\n")
            if code or not report.get("success"):
                raise RuntimeError(f"{phase}: {report.get('failure', 'process-failure')} (exit {code})")
            print(f"{phase}: {len(report['checks'])} checks passed in {report['process_seconds']:.2f}s", flush=True)
    finally:
        server.shutdown()
        server.server_close()
    journey = json.loads((args.output / "journey.json").read_text())
    performance = performance_result(journey["metrics"])
    (args.output / "performance.json").write_text(json.dumps(performance, indent=2) + "\n")
    if not all(result["passed"] for result in performance.values()):
        raise RuntimeError("Performance budget exceeded; inspect performance.json")
    print(f"Release evidence: {args.output.resolve()}")
    print(f"Isolated QA container retained for inspection: {root.parents[3]}")


if __name__ == "__main__":
    main()
