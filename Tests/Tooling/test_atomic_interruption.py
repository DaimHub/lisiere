"""SIGKILL interrupts the real Swift atomic writer; only complete snapshots may remain."""
from pathlib import Path
import plistlib
import select
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == "darwin", "The app and its StoreFile implementation target macOS")
class AtomicInterruptionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix="lisiere-atomic-")
        cls.binary = Path(cls.build.name) / "writer"
        result = subprocess.run(["xcrun", "swiftc", "-O", "-parse-as-library", "-swift-version", "6",
                                str(ROOT / "Sources/Browser/StoreFile.swift"), str(ROOT / "Sources/Browser/Diagnostics.swift"),
                                str(ROOT / "Tests/Tooling/AtomicWriter.swift"), "-o", str(cls.binary)], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def test_killed_writers_never_leave_partial_snapshots(self):
        with tempfile.TemporaryDirectory(prefix="lisiere-interruption-") as directory:
            path = Path(directory) / "Session.plist"
            for delay in [0.001, 0.003, 0.007, 0.013, 0.029, 0.043, 0.061, 0.097]:
                process = subprocess.Popen([str(self.binary), str(path)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                try:
                    self.assertTrue(select.select([process.stdout], [], [], 15)[0], "Writer never became ready")
                    self.assertEqual(process.stdout.readline(), b"ready\n")
                    time.sleep(delay)
                finally:
                    process.kill()
                    process.wait(timeout=5)
                    process.stdout.close()
                snapshot = plistlib.loads(path.read_bytes())
                self.assertGreaterEqual(snapshot["sequence"], 1)
                self.assertEqual(snapshot["payload"], bytes([snapshot["sequence"] % 251]) * 1_048_576)
