import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("release_metadata", ROOT / "scripts/release-metadata.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleaseMetadataTests(unittest.TestCase):
    def test_actual_project_selects_sparkle_and_keeps_prerelease_out_of_bundle_version(self):
        values = module.metadata((ROOT / "project.yml").read_text(), "v1.2.3-rc.1")
        self.assertEqual(values["SPARKLE_VERSION"], "2.10.0")
        self.assertEqual(values["MARKETING_VERSION"], "1.2.3")
        self.assertEqual(values["VERSION"], "1.2.3-rc.1")
        self.assertTrue(all("\n" not in v for v in values.values()))

    def test_invalid_or_injected_tags_are_rejected(self):
        project = (ROOT / "project.yml").read_text()
        for tag in ["1.2.3", "v1.2", "v01.2.3", "v1.2.3\nINJECTED=yes", "v1.2.3/../../"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                module.metadata(project, tag)

    def test_missing_ambiguous_or_unpinned_sparkle_is_rejected(self):
        for project in ["", "  Sparkle:\n    from: 2.10.0\n",
                        "  Sparkle:\n    exactVersion: 2.10.0\n  Sparkle:\n    exactVersion: 2.10.0\n"]:
            with self.assertRaises(ValueError):
                module.metadata(project, "v1.2.3")
