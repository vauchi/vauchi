# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


WORKSPACE_ROOT = Path(sys.argv.pop(1)).resolve()

# Root-repo CI checks out only this repo, so _private/ is absent there and every
# link into it dangles. Assertions must therefore read link TARGETS
# (os.readlink works on a dangling link) rather than resolve them; anything that
# needs the canonical tree present goes behind this flag.
CANONICAL_CODEX = WORKSPACE_ROOT / "_private/.codex"
CANONICAL_PRESENT = CANONICAL_CODEX.is_dir()

# Named explicitly rather than derived from whatever .codex happens to contain.
# Deriving both sides of the comparison from the same listing is a tautology: it
# proves every present entry points at its own name and nothing about the six
# that could be missing, so CI stayed green with only config.toml linked while
# Codex would have loaded no hooks at all.
REQUIRED_CODEX_ENTRIES = frozenset(
    {"agents", "config.toml", "docs", "hooks", "README.md", "rules", "skills"}
)

LAYOUT_LIB = WORKSPACE_ROOT / "just/codex-layout-lib.sh"


class CodexLayoutTest(unittest.TestCase):
    def test_agents_root_is_a_real_directory(self) -> None:
        agents_root = WORKSPACE_ROOT / ".agents"

        self.assertTrue(agents_root.is_dir())
        self.assertFalse(agents_root.is_symlink())

    def test_skills_link_targets_the_canonical_tree(self) -> None:
        skills_link = WORKSPACE_ROOT / ".agents/skills"

        self.assertTrue(skills_link.is_symlink())
        self.assertEqual(os.readlink(skills_link), "../_private/.claude/skills")


class CodexConfigRootLayoutTest(unittest.TestCase):
    """Codex bind-mounts <root>/.codex read-only, and bubblewrap refuses to
    enforce a read-only path that crosses a writable symlink. A symlinked
    .codex therefore fails EVERY sandboxed command with "cannot enforce
    sandbox read-only path ... because it crosses writable symlink", while
    read-only mode keeps working — which is how it stayed hidden.

    These assertions pin startup compatibility, not a security boundary: the
    entries are symlinks into writable _private, so a sandboxed session can
    still rewrite its own hooks through them. See just/codex-layout-lib.sh.
    """

    def test_codex_root_is_a_real_directory(self) -> None:
        codex_root = WORKSPACE_ROOT / ".codex"

        self.assertTrue(codex_root.is_dir())
        self.assertFalse(codex_root.is_symlink())

    def test_every_required_entry_is_present_and_linked(self) -> None:
        entries = sorted((WORKSPACE_ROOT / ".codex").iterdir())

        actual = {
            entry.name: os.readlink(entry) if entry.is_symlink() else None for entry in entries
        }
        expected = {name: f"../_private/.codex/{name}" for name in REQUIRED_CODEX_ENTRIES}

        # Subset, not equality: a new entry in the canonical tree is fine, a
        # missing or mis-targeted required one is not.
        self.assertEqual({k: actual.get(k) for k in expected}, expected)

    def test_no_entry_is_a_real_file(self) -> None:
        """A real file here is content that _private can never track, and it
        silently shadows the canonical copy.
        """
        strays = [
            entry.name
            for entry in (WORKSPACE_ROOT / ".codex").iterdir()
            if not entry.is_symlink()
        ]

        self.assertEqual(strays, [])

    def test_config_link_targets_the_canonical_tree(self) -> None:
        config = WORKSPACE_ROOT / ".codex/config.toml"

        self.assertTrue(config.is_symlink())
        self.assertEqual(os.readlink(config), "../_private/.codex/config.toml")

    @unittest.skipUnless(CANONICAL_PRESENT, "_private not cloned (root-repo CI)")
    def test_links_resolve_when_private_is_cloned(self) -> None:
        """In a full workspace the links must actually resolve — a dangling
        entry means Codex silently loads no project hooks at all.
        """
        config = WORKSPACE_ROOT / ".codex/config.toml"

        self.assertTrue(config.is_file(), "dangling link — Codex would load no project hooks")
        self.assertEqual(config.resolve(), (CANONICAL_CODEX / "config.toml").resolve())

        linked = {entry.name for entry in (WORKSPACE_ROOT / ".codex").iterdir()}
        canonical = {entry.name for entry in CANONICAL_CODEX.iterdir()}

        self.assertEqual(linked, canonical)


class CheckCodexLayoutTest(unittest.TestCase):
    """Exercises check_codex_layout() itself against a throwaway workspace.

    session-init and session-end both depend on this function to repair and
    gate the layout, but nothing executed it — the shape assertions above only
    describe the tree it is supposed to produce. Uses a fixture rather than the
    real tree, so it runs in CI without _private.
    """

    def run_check(self, root: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", "-c", f'source "{LAYOUT_LIB}"; check_codex_layout'],
            cwd=root,
            capture_output=True,
            text=True,
        )

    def make_workspace(self, root: Path) -> Path:
        """A minimal workspace in the pre-fix shape: canonical tree in
        _private, root .codex still a symlink.
        """
        canonical = root / "_private/.codex"
        canonical.mkdir(parents=True)
        (canonical / "config.toml").write_text('sandbox_mode = "workspace-write"\n', encoding="utf-8")
        (canonical / "hooks").mkdir()
        (root / ".codex").symlink_to("_private/.codex")
        return root

    def test_converts_a_symlinked_root(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = self.make_workspace(Path(tmp))

            result = self.run_check(root)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((root / ".codex").is_symlink())
            self.assertTrue((root / ".codex").is_dir())
            self.assertEqual(
                os.readlink(root / ".codex/config.toml"), "../_private/.codex/config.toml"
            )
            self.assertTrue((root / ".codex/config.toml").is_file(), "link must resolve")

    def test_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = self.make_workspace(Path(tmp))
            self.run_check(root)

            second = self.run_check(root)

            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(second.stdout.strip(), "", "a sound layout must report nothing")

    def test_repairs_a_missing_link(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = self.make_workspace(Path(tmp))
            self.run_check(root)
            (root / ".codex/hooks").unlink()

            result = self.run_check(root)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(os.readlink(root / ".codex/hooks"), "../_private/.codex/hooks")

    def test_fails_on_a_stray(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = self.make_workspace(Path(tmp))
            self.run_check(root)
            (root / ".codex/leftover.toml").write_text("orphan\n", encoding="utf-8")

            result = self.run_check(root)

            self.assertEqual(result.returncode, 1)
            self.assertIn("leftover.toml", result.stdout)

    def test_fails_without_a_canonical_tree(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = self.run_check(Path(tmp))

            self.assertEqual(result.returncode, 1)
            self.assertIn("_private/.codex", result.stdout)

    def test_claude_and_kimi_roots_stay_symlinks(self) -> None:
        """The asymmetry with .codex is deliberate, not drift: neither Claude
        Code nor Kimi bind-mounts its config dir, and Claude Code only
        discovers project config at the workspace root.
        """
        for name in (".claude", ".kimi-code"):
            with self.subTest(root=name):
                root = WORKSPACE_ROOT / name

                self.assertTrue(root.is_symlink())
                self.assertEqual(os.readlink(root), f"_private/{name}")


if __name__ == "__main__":
    unittest.main()
