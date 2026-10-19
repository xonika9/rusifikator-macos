#!/usr/bin/env python3
"""Exercise release guards in disposable repositories, without Keychain or builds."""

import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parent.parent


class ReleaseScriptTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="rusifikator-release-tests-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.scripts = self.root / "scripts"
        self.scripts.mkdir()
        for name in (
            "release-metadata.sh", "release-checks.sh", "verify-release-artifacts.sh"
        ):
            shutil.copy2(REPOSITORY / "scripts" / name, self.scripts / name)
        resources = self.root / "Sources/Rusifikator/Resources"
        resources.mkdir(parents=True)
        (resources / "Rusifikator-Info.plist").write_bytes(plistlib.dumps({
            "CFBundleShortVersionString": "1.4",
            "CFBundleVersion": "1.4.0",
            "SUFeedURL": "https://example.invalid/appcast.xml",
            "SUPublicEDKey": "fixture-public-key",
        }))
        self.tools = self.root / ".build/artifacts/sparkle/Sparkle/bin"
        self.tools.mkdir(parents=True)
        # The guard owns invoking Sparkle and propagating its result, not crypto.
        self.write_executable(self.tools / "sign_update", '''#!/bin/zsh
[[ "$1" == --verify && "$3" == fixture-signature && "$(<"$2")" == fixture-disk-image ]]
''')

    def write_executable(self, path, text):
        path.write_text(text)
        path.chmod(0o755)

    def run_script(self, name, *arguments, env=None):
        return subprocess.run(
            ["/bin/zsh", str(self.scripts / name), *map(str, arguments)],
            cwd=self.root, env=env, text=True, capture_output=True, timeout=20,
        )

    def make_artifacts(self, directory, signature="fixture-signature"):
        directory.mkdir(parents=True)
        image = directory / "Rusifikator-1.4.0.dmg"
        image.write_text("fixture-disk-image")
        appcast = directory / "appcast.xml"
        appcast.write_text(f'''<sparkle:version>1.4.0</sparkle:version>
<sparkle:shortVersionString>1.4</sparkle:shortVersionString>
<enclosure url="https://github.com/xonika9/rusifikator-macos/releases/download/v1.4.0/Rusifikator-1.4.0.dmg" sparkle:edSignature="{signature}" />
''')
        (directory / "SHA256SUMS").write_text("".join(
            hashlib.sha256(path.read_bytes()).hexdigest() + "  " + path.name + "\n"
            for path in (image, appcast)
        ))

    def test_secret_scan_reports_files_without_disclosing_matching_text(self):
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        (self.root / "CHANGELOG.md").write_text("## 1.4.0 — 2026-10-19\n")
        candidate = self.root / "candidate.txt"
        candidate.write_text("")
        subprocess.run(["git", "add", "candidate.txt"], cwd=self.root, check=True)
        fake_bin = self.root / "bin"
        fake_bin.mkdir()
        self.write_executable(fake_bin / "swift", "#!/bin/sh\nexit 0\n")
        for name in (
            "test-system-prompt.sh", "package-app.sh", "smoke-test-app.sh",
            "build-release-artifacts.sh",
        ):
            self.write_executable(self.scripts / name, "#!/bin/sh\nexit 0\n")
        env = dict(os.environ, PATH=str(fake_bin) + os.pathsep + os.environ["PATH"])
        for marker in (
            "sk-" + "A" * 24,
            "ghp_" + "B" * 24,
            "github_pat_" + "C" * 24,
            "-----BEGIN RSA " + "PRIVATE KEY-----",
        ):
            with self.subTest(prefix=marker[:3]):
                candidate.write_text(marker + "\n")
                result = self.run_script("release-checks.sh", env=env)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("candidate.txt", result.stderr)
                self.assertNotIn(marker, result.stdout + result.stderr)
        candidate.write_text("ordinary text\n")
        result = self.run_script("release-checks.sh", env=env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

        self.write_executable(
            fake_bin / "git", "#!/bin/sh\necho 'untrusted scanner diagnostic' >&2\nexit 2\n"
        )
        result = self.run_script("release-checks.sh", env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exit 2", result.stderr)
        self.assertNotIn("untrusted scanner diagnostic", result.stdout + result.stderr)

    def test_missing_signature_tool_blocks_verification(self):
        artifacts = self.root / "dist/release"
        self.make_artifacts(artifacts)
        (artifacts / "RELEASE_NOTES.md").write_text("Fixture notes\n")
        (self.tools / "sign_update").unlink()
        result = self.run_script("verify-release-artifacts.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("sign_update", result.stderr)

    def test_downloaded_artifacts_are_verified_without_local_release_notes(self):
        # This is exactly the three-file public attachment set, in a path with spaces.
        downloaded = self.root / "downloaded release"
        self.make_artifacts(downloaded)
        result = self.run_script("verify-release-artifacts.sh", downloaded)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_invalid_downloaded_signature_is_rejected(self):
        downloaded = self.root / "downloaded"
        self.make_artifacts(downloaded, signature="invalid-signature")
        result = self.run_script("verify-release-artifacts.sh", downloaded)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("signature", result.stderr)

    def test_downloaded_checksums_are_checked(self):
        downloaded = self.root / "downloaded"
        self.make_artifacts(downloaded)
        (downloaded / "appcast.xml").write_text(
            (downloaded / "appcast.xml").read_text() + "<!-- changed after hashing -->\n"
        )
        result = self.run_script("verify-release-artifacts.sh", downloaded)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Checksums", result.stderr)

    def test_default_verification_still_requires_local_notes(self):
        artifacts = self.root / "dist/release"
        self.make_artifacts(artifacts)
        notes = artifacts / "RELEASE_NOTES.md"
        notes.write_text("Fixture notes\n")
        result = self.run_script("verify-release-artifacts.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        notes.unlink()
        result = self.run_script("verify-release-artifacts.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Release notes", result.stderr)


if __name__ == "__main__":
    unittest.main()
