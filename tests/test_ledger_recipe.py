# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Coverage for `just ledger`, the intervention-ledger append recipe.

The recipe validates four closed vocabularies and a line-length cap, and
none of that had ever been proven to reject anything — the same gap that
let VGT09 sit dead for a month with a green self-test (2026-08-21 audit).

`defect-class` is the field this file exists for. Four weeks of entries
were classified after the fact, by reading 17-character free-text notes
and guessing; that judgement was load-bearing for the direction-0
findings and nobody checked it. Recording the class at capture time
replaces the guess with a `uniq -c`.
"""

from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
LEDGER_REL = Path("_private/docs/intervention-ledger.md")

VALID = ["gate", "lt5m", "review", "prevented-defect", "unverified-claim"]


def run_ledger(workspace: Path, args: list[str]) -> subprocess.CompletedProcess:
    """Invoke `just ledger` against a throwaway ledger under `workspace`."""
    return subprocess.run(
        ["just", "ledger", *args],
        cwd=workspace,
        capture_output=True,
        text=True,
    )


class LedgerRecipeTests(unittest.TestCase):
    """The recipe must reject bad input and record the defect class."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.workspace = Path(self._tmp.name)
        # A workspace is just the justfile tree plus a seeded ledger.
        for entry in ("justfile", "just"):
            source = ROOT / entry
            target = self.workspace / entry
            if source.is_dir():
                subprocess.run(["cp", "-R", str(source), str(target)], check=True)
            else:
                target.write_bytes(source.read_bytes())
        ledger = self.workspace / LEDGER_REL
        ledger.parent.mkdir(parents=True, exist_ok=True)
        ledger.write_text("# Intervention ledger\n\n## Entries\n", encoding="utf-8")
        self.ledger = ledger

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _entries(self) -> list[str]:
        return [l for l in self.ledger.read_text(encoding="utf-8").splitlines() if l.startswith("- 20")]

    def test_appends_a_well_formed_entry_with_its_defect_class(self) -> None:
        result = run_ledger(self.workspace, VALID + ["gate", "hid", "clippy"])
        self.assertEqual(result.returncode, 0, result.stderr)
        entries = self._entries()
        self.assertEqual(len(entries), 1)
        fields = [f.strip() for f in entries[0].lstrip("- ").split("|")]
        self.assertEqual(fields[1:5], VALID[:4])
        self.assertEqual(fields[5], "`unverified-claim`")
        self.assertEqual(fields[6], "gate hid clippy")

    def test_a_note_is_recorded_as_typed_and_never_run(self) -> None:
        """private#679: the note was pasted into the script source, so a
        backticked word ran as a command and a quote ended the string."""
        note = ["`touch", "x`", "$(ls)", '"']

        result = run_ledger(self.workspace, VALID + note)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        fields = [f.strip() for f in self._entries()[0].lstrip("- ").split("|")]
        self.assertEqual(fields[6], " ".join(note))
        self.assertEqual(sorted(p.name for p in self.workspace.iterdir()),
                         ["_private", "just", "justfile"])

    def test_rejects_an_unknown_defect_class(self) -> None:
        result = run_ledger(self.workspace, VALID[:4] + ["misc", "note"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("defect-class must be", result.stdout + result.stderr)
        self.assertEqual(self._entries(), [])

    def test_rejects_each_unknown_vocabulary_value(self) -> None:
        for index, label in enumerate(("area", "bucket", "kind", "outcome")):
            with self.subTest(field=label):
                args = list(VALID)
                args[index] = "bogus"
                result = run_ledger(self.workspace, args + ["note"])
                self.assertNotEqual(result.returncode, 0, f"{label} accepted 'bogus'")
                self.assertEqual(self._entries(), [])

    def test_rejects_a_note_that_overflows_the_line_cap(self) -> None:
        result = run_ledger(self.workspace, VALID + ["x" * 200])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self._entries(), [])

    def test_the_defect_class_costs_the_note_nothing(self) -> None:
        """The custom line-length rule exempts backtick spans, so emitting
        the class as code costs the note only the ` | ` separator: the
        budget goes from 23 characters to 20, not to the 7 it would be if
        the class counted. Measured, not assumed."""
        result = run_ledger(self.workspace, VALID + ["twenty chars exactly"])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("twenty chars exactly", self._entries()[0])

        over = run_ledger(self.workspace, VALID + ["twenty-one chars here!"])
        self.assertNotEqual(over.returncode, 0, "the cap must still bite")

    def test_a_note_is_optional(self) -> None:
        result = run_ledger(self.workspace, VALID)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self._entries()[0].endswith("`unverified-claim`"))

    def test_entries_stay_parseable_by_the_seven_day_counter(self) -> None:
        """session-end counts with awk on `$2`, so the date must stay the
        second whitespace-separated token however many fields follow."""
        run_ledger(self.workspace, VALID + ["a note"])
        self.assertRegex(self._entries()[0].split()[1], r"^\d{4}-\d{2}-\d{2}$")

    def test_accepts_the_infra_and_handback_areas(self) -> None:
        """`other` had grown to 65% of entries (private#466), hiding the two
        clusters inside it: CI-host and deploy state, and actions only the
        maintainer may take."""
        for area in ("infra", "handback"):
            with self.subTest(area=area):
                result = run_ledger(self.workspace, [area] + VALID[1:] + ["note"])
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(f"| {area} |", self._entries()[-1])


if __name__ == "__main__":
    unittest.main()
