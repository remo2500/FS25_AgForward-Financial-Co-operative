from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile


REPO_ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = REPO_ROOT / "tools" / "build_mod_package.py"
spec = importlib.util.spec_from_file_location("build_mod_package", MODULE_PATH)
assert spec and spec.loader
build_mod_package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_mod_package)


class PackageBuilderTests(unittest.TestCase):
    def make_repo(self, root: Path) -> None:
        (root / "src").mkdir(parents=True)
        (root / "l10n").mkdir()
        (root / "docs").mkdir()
        (root / "tests").mkdir()
        (root / "tools").mkdir()
        (root / ".github").mkdir()
        (root / "gui").mkdir()
        (root / "images").mkdir()
        (root / "modDesc.xml").write_text(
            """<?xml version=\"1.0\" encoding=\"utf-8\"?>
<modDesc descVersion=\"113\">
  <title><en>Test</en></title>
  <iconFilename>images/icon.png</iconFilename>
  <extraSourceFiles>
    <sourceFile filename=\"src/Main.lua\"/>
  </extraSourceFiles>
  <l10n filenamePrefix=\"l10n/l10n\"/>
</modDesc>
""",
            encoding="utf-8",
        )
        (root / "src" / "Main.lua").write_text("Test = {}\n", encoding="utf-8")
        # This is a deliberate offline-only source. Merely existing in src must
        # not make it part of a runtime package.
        (root / "src" / "OfflineResearch.lua").write_text("Offline = {}\n", encoding="utf-8")
        (root / "l10n" / "l10n_en.xml").write_text("<l10n/>\n", encoding="utf-8")
        (root / "l10n" / "l10n_de.xml").write_text("<l10n/>\n", encoding="utf-8")
        (root / "images" / "icon.png").write_bytes(b"fake-png")
        (root / "gui" / "frame.xml").write_text("<GUI/>\n", encoding="utf-8")
        (root / "LICENSE").write_text("test license\n", encoding="utf-8")
        (root / "README.md").write_text("dev readme\n", encoding="utf-8")
        (root / "docs" / "spec.md").write_text("dev doc\n", encoding="utf-8")
        (root / "tests" / "test.lua").write_text("dev test\n", encoding="utf-8")
        (root / "tools" / "tool.py").write_text("dev tool\n", encoding="utf-8")
        (root / ".github" / "workflow.yml").write_text("dev workflow\n", encoding="utf-8")

    def test_build_contains_only_explicit_runtime_files(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "repo"
            root.mkdir()
            self.make_repo(root)
            output = Path(temp) / "FS25_AgForwardFinance.zip"
            result = build_mod_package.build(root, output)
            self.assertTrue(output.is_file())
            with zipfile.ZipFile(output, "r") as archive:
                names = set(archive.namelist())

            expected = {
                "modDesc.xml",
                "src/Main.lua",
                "l10n/l10n_en.xml",
                "l10n/l10n_de.xml",
                "images/icon.png",
                "LICENSE",
            }
            self.assertEqual(names, expected)
            self.assertEqual(set(result["manifest"]), expected)
            self.assertNotIn("src/OfflineResearch.lua", names)
            self.assertNotIn("gui/frame.xml", names)
            self.assertNotIn("README.md", names)
            self.assertNotIn("docs/spec.md", names)
            self.assertNotIn("tests/test.lua", names)
            self.assertNotIn("tools/tool.py", names)
            self.assertNotIn(".github/workflow.yml", names)

    def test_runtime_manifest_explicitly_promotes_gui_resources(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "repo"
            root.mkdir()
            self.make_repo(root)
            (root / "runtime_package_manifest.txt").write_text(
                "# Explicit non-modDesc resources\n"
                "gui/*.xml\n",
                encoding="utf-8",
            )
            output = Path(temp) / "FS25_AgForwardFinance.zip"
            result = build_mod_package.build(root, output)
            self.assertIn("gui/frame.xml", result["manifest"])
            with zipfile.ZipFile(output, "r") as archive:
                self.assertIn("gui/frame.xml", archive.namelist())
                self.assertNotIn("src/OfflineResearch.lua", archive.namelist())

    def test_manifest_cannot_promote_development_directories(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "repo"
            root.mkdir()
            self.make_repo(root)
            (root / "runtime_package_manifest.txt").write_text("docs/spec.md\n", encoding="utf-8")
            output = Path(temp) / "bad.zip"
            with self.assertRaisesRegex(ValueError, "may not include development path"):
                build_mod_package.build(root, output)
            self.assertFalse(output.exists())

    def test_missing_moddesc_source_fails_before_zip(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "repo"
            root.mkdir()
            self.make_repo(root)
            (root / "src" / "Main.lua").unlink()
            output = Path(temp) / "broken.zip"
            with self.assertRaisesRegex(ValueError, "sourceFile missing"):
                build_mod_package.build(root, output)
            self.assertFalse(output.exists())

    def test_missing_localization_prefix_fails_before_zip(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "repo"
            root.mkdir()
            self.make_repo(root)
            (root / "l10n" / "l10n_en.xml").unlink()
            (root / "l10n" / "l10n_de.xml").unlink()
            output = Path(temp) / "broken.zip"
            with self.assertRaisesRegex(ValueError, "no localization files"):
                build_mod_package.build(root, output)
            self.assertFalse(output.exists())

    def test_missing_moddesc_icon_fails_before_zip(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "repo"
            root.mkdir()
            self.make_repo(root)
            (root / "images" / "icon.png").unlink()
            output = Path(temp) / "broken.zip"
            with self.assertRaisesRegex(ValueError, "iconFilename.*missing"):
                build_mod_package.build(root, output)
            self.assertFalse(output.exists())

    def test_build_is_deterministic_for_same_repository_state(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "repo"
            root.mkdir()
            self.make_repo(root)
            first = Path(temp) / "first.zip"
            second = Path(temp) / "second.zip"
            first_result = build_mod_package.build(root, first)
            second_result = build_mod_package.build(root, second)
            self.assertEqual(first_result["sha256"], second_result["sha256"])
            self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_output_inside_repository_is_not_selected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "repo"
            root.mkdir()
            self.make_repo(root)
            dist = root / "dist"
            output = dist / "FS25_AgForwardFinance.zip"
            build_mod_package.build(root, output)
            with zipfile.ZipFile(output, "r") as archive:
                self.assertNotIn("dist/FS25_AgForwardFinance.zip", archive.namelist())

    def test_unsafe_manifest_path_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "repo"
            root.mkdir()
            self.make_repo(root)
            (root / "runtime_package_manifest.txt").write_text("../escape.txt\n", encoding="utf-8")
            output = Path(temp) / "bad.zip"
            with self.assertRaisesRegex(ValueError, "unsafe repository path"):
                build_mod_package.build(root, output)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
