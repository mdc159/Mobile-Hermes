#!/usr/bin/env python3
"""Tests for Studio54 mobile-edge grid readiness artifacts."""

from __future__ import annotations

import os
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
INSTALL = ROOT / "scripts" / "install-hermes-on-s24"
VERIFY = INSTALL / "verify-grid-readiness.sh"
WRAPPER = INSTALL / "phone" / "bin" / "mobile-hermes-attach.template"
DOC = ROOT / "docs" / "mobile-hermes-grid-readiness.md"

TAILNET_IP_RE = re.compile(r"\b100(?:\.\d{1,3}){3}\b")
SECRETISH_RE = re.compile(r"(?i)(api[_-]?key|token|password|secret)\s*[:=]\s*[^\s\]\)}`]+")


def run(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run(
        args,
        cwd=INSTALL,
        env=merged_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


class GridReadinessTests(unittest.TestCase):
    def test_verify_grid_readiness_sample_is_redacted_yaml_contract(self) -> None:
        result = run("bash", str(VERIFY), "--sample")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("candidate: Android", result.stdout)
        self.assertIn("host_details_redacted: true", result.stdout)
        self.assertIn("secrets_printed: false", result.stdout)
        self.assertIn("raw_runtime_logs_preserved: false", result.stdout)
        self.assertIn("installs_performed: false", result.stdout)
        self.assertIn("services_changed: false", result.stdout)
        self.assertIsNone(TAILNET_IP_RE.search(result.stdout))
        self.assertIsNone(SECRETISH_RE.search(result.stdout))

    def test_verify_grid_readiness_dry_run_does_not_execute_remote_commands(self) -> None:
        result = run("bash", str(VERIFY), "--dry-run", env={"PHONE_HOST": "example-phone"})

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("mode: dry-run", result.stdout)
        self.assertIn("ssh_alias_configured:", result.stdout)
        self.assertIn("tailscale_reachable: unknown", result.stdout)
        self.assertIn("installs_performed: false", result.stdout)
        self.assertIn("services_changed: false", result.stdout)
        self.assertIn("next_action:", result.stdout)
        self.assertNotIn("example-phone", result.stdout)
        self.assertIsNone(TAILNET_IP_RE.search(result.stdout))

    def test_attach_wrapper_template_is_non_mutating_attach_only(self) -> None:
        content = WRAPPER.read_text()

        self.assertIn("tmux attach-session", content)
        self.assertNotIn("new-session", content)
        self.assertNotIn("pkg install", content)
        self.assertNotIn("apt install", content)
        self.assertNotIn("llama-server", content)
        self.assertIn("HERMES_GRID_TMUX_SESSION", content)
        self.assertIn("HERMES_GRID_TMUX_WINDOW", content)

    def test_readiness_doc_links_phase_a_artifacts(self) -> None:
        content = DOC.read_text()

        self.assertIn("verify-grid-readiness.sh", content)
        self.assertIn("mobile-hermes-attach.template", content)
        self.assertIn("Phase A", content)
        self.assertIn("Do not enable", content)


if __name__ == "__main__":
    unittest.main()
