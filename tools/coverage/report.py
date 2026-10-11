"""Render measured, repository-owned LCOV line coverage without dependencies."""

from __future__ import annotations

import argparse
import html
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import re


def source_path(value: str, root: str, language: str) -> str | None:
    # #[path = "../src/..."] integration modules have a tests/../src path
    # in LLVM. Normalize before scoping and merging with the library mapping.
    value = posixpath.normpath(value.replace("\\", "/"))
    root = posixpath.normpath(root.replace("\\", "/")).rstrip("/") + "/"
    if re.match(r"^(?:[A-Za-z]:/|/)", value):
        # MSVC/LLVM can use a different drive-letter case than Python.
        windows = bool(re.match(r"^[A-Za-z]:/", root))
        candidate, prefix = (value.casefold(), root.casefold()) if windows else (value, root)
        if not candidate.startswith(prefix):
            return None
        value = value[len(root):]
    if language == "rust" and value.startswith("src/"):
        value = "rust/" + value
    path = PurePosixPath(value)
    if ".." in path.parts or "\0" in value:
        return None
    value = path.as_posix()
    prefix, suffix = ("lib/", ".dart") if language == "flutter" else ("rust/src/", ".rs")
    if not value.startswith(prefix) or not value.endswith(suffix):
        return None
    if path.name.startswith("frb_generated") or value.endswith((".g.dart", ".freezed.dart")):
        return None
    if value == "rust/src/ipc_tests.rs":
        return None
    return value


def parse_lcov(content: str, root: str, language: str) -> dict[str, dict[int, int]]:
    files: dict[str, dict[int, int]] = {}
    active = False
    path = None
    lines: dict[int, int] = {}
    for number, record in enumerate(content.splitlines(), 1):
        if record.startswith("SF:"):
            if active:
                raise ValueError(f"LCOV record missing end_of_record before line {number}")
            active = True
            path = source_path(record[3:], root, language)
            lines = {}
        elif record.startswith("DA:"):
            if not active:
                raise ValueError(f"LCOV line data has no source at line {number}")
            fields = record[3:].split(",")
            if len(fields) not in (2, 3):
                raise ValueError(f"Invalid LCOV line data at line {number}")
            line, hits = int(fields[0]), int(fields[1])
            if line < 1 or hits < 0:
                raise ValueError(f"Invalid LCOV line/count at line {number}")
            lines[line] = lines.get(line, 0) + hits
        elif record == "end_of_record":
            if not active:
                raise ValueError(f"LCOV end_of_record has no source at line {number}")
            if path is not None and lines:
                target = files.setdefault(path, {})
                for line, hits in lines.items():
                    target[line] = target.get(line, 0) + hits
            active = False
    if active:
        raise ValueError("LCOV ends with an incomplete record")
    if not files:
        raise ValueError("LCOV contains no measured Neura production lines")
    return files


def percentage(covered: int, total: int) -> str:
    return f"{100 * covered / total:.2f}%"


def line_ranges(lines: list[int]) -> str:
    ranges = []
    for line in sorted(lines):
        if ranges and ranges[-1][1] + 1 == line:
            ranges[-1][1] = line
        else:
            ranges.append([line, line])
    return ", ".join(str(first) if first == last else f"{first}-{last}" for first, last in ranges)


def make_report(files: dict[str, dict[int, int]], root: Path, language: str,
                label: str, commit: str, test_outcome: str) -> dict:
    measured = []
    for path, lines in sorted(files.items()):
        missing = sorted(line for line, hits in lines.items() if hits == 0)
        measured.append({"path": path, "covered": len(lines) - len(missing),
                         "total": len(lines), "uncovered_lines": missing})
    inventory_root = root / ("lib" if language == "flutter" else "rust/src")
    suffix = "*.dart" if language == "flutter" else "*.rs"
    inventory = {path.relative_to(root).as_posix() for path in inventory_root.rglob(suffix)
                 if source_path(path.relative_to(root).as_posix(), str(root), language)}
    return {"language": language, "label": label, "tested_commit": commit,
            "test_outcome": test_outcome, "complete_test_run": test_outcome == "success",
            "covered": sum(item["covered"] for item in measured),
            "total": sum(item["total"] for item in measured), "files": measured,
            "unmeasured_files": sorted(inventory - files.keys())}


def write_report(report: dict, output: Path) -> str:
    output.mkdir(parents=True, exist_ok=True)
    rate = percentage(report["covered"], report["total"])
    state = "Complete test run" if report["complete_test_run"] else "PARTIAL: tests did not pass"
    # Include only paths and counts: no source text, transcripts, credentials,
    # test logs, vault data, or raw process profiles enter these reports.
    note = ("Line coverage of measured production sources only. Unmeasured files have unknown "
            "executable-line counts; they are listed separately, not counted as covered. "
            "Generated bridge/model files and the Rust IPC test helper are excluded. "
            "No minimum coverage threshold is enforced.")
    title = f"Neura coverage: {report['label']}"
    markdown = (f"### {title}\n\n{state}; test outcome: `{report['test_outcome']}`.\n\n"
                f"Tested commit: `{report['tested_commit']}`.\n\n"
                f"**Measured line coverage: {rate}** "
                f"({report['covered']}/{report['total']} lines; {len(report['files'])} files).\n\n"
                f"{note}\n\nUnmeasured source files: {len(report['unmeasured_files'])}.\n\n"
                "Download the coverage artifact for `index.html`, `summary.json`, "
                "and the original `raw.lcov.info`.\n")
    rows = []
    for item in report["files"]:
        missing = line_ranges(item["uncovered_lines"]) or "None"
        rows.append(f"<tr><td><code>{html.escape(item['path'])}</code></td>"
                    f"<td>{percentage(item['covered'], item['total'])}</td>"
                    f"<td>{item['covered']}/{item['total']}</td>"
                    f"<td>{missing}</td></tr>")
    unmeasured = "".join(f"<li><code>{html.escape(path)}</code></li>"
                         for path in report["unmeasured_files"]) or "<li>None</li>"
    page = ("<!doctype html><html lang='en'><meta charset='utf-8'>"
            "<meta name='viewport' content='width=device-width, initial-scale=1'>"
            f"<title>{html.escape(title)}</title>"
            "<style>body{font:16px system-ui;margin:2rem;color:#17243b}"
            "table{border-collapse:collapse;width:100%}th,td{border:1px solid #bdc8da;"
            "padding:.65rem;text-align:left;vertical-align:top}"
            "th{background:#edf2fa}code{overflow-wrap:anywhere}"
            "td:last-child{max-width:35rem;overflow-wrap:anywhere}</style>"
            f"<h1>{html.escape(title)}</h1><p><strong>{html.escape(state)}</strong>; "
            f"test outcome: {html.escape(report['test_outcome'])}</p>"
            f"<p>Tested commit: <code>{html.escape(report['tested_commit'])}</code></p>"
            f"<h2>{rate} ({report['covered']}/{report['total']} measured lines)</h2>"
            f"<p>{note}</p><table><thead><tr><th>Source</th><th>Line coverage</th>"
            "<th>Covered/total</th><th>Uncovered lines</th></tr></thead><tbody>"
            f"{''.join(rows)}</tbody></table>"
            f"<h2>Unmeasured files ({len(report['unmeasured_files'])})</h2>"
            "<p>These may be unimported Dart libraries or platform-specific Rust sources "
            "not compiled on this runner. Their coverage is unknown.</p>"
            f"<ul>{unmeasured}</ul></html>")
    (output / "index.html").write_text(page, encoding="utf-8")
    (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    (output / "summary.md").write_text(markdown, encoding="utf-8")
    return markdown


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lcov", type=Path, required=True)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--language", choices=("flutter", "rust"), required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--test-outcome", choices=("success", "failure", "cancelled"), required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    files = parse_lcov(args.lcov.read_text(encoding="utf-8-sig"), str(root), args.language)
    report = make_report(files, root, args.language, args.label, args.commit, args.test_outcome)
    markdown = write_report(report, args.output)
    if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(summary).open("a", encoding="utf-8") as stream:
            stream.write(markdown)
    print(markdown)


if __name__ == "__main__":
    main()
