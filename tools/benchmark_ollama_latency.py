"""Opt-in, foreground Windows DLL comparison. No files, downloads or cloud calls.

Only fixed synthetic questions enter the existing Ollama ABI. Stdout contains
numeric timings, binary hashes and fixed labels, never prompts/replies/errors.
This measures native adapter delivery, not Flutter frames, TTS or GPU cessation.
"""
from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
import hashlib
import http.client
import json
import math
import os
import re
import statistics
from pathlib import Path
import subprocess
import sys
import threading
import time


FIXTURES = (
    ("arithmetic", "What is 2 plus 2? Reply with the number only."),
    ("planning", "Give three short steps to tidy a desk in five minutes."),
    ("uncertainty", "Can you guarantee that every plan will succeed? Explain briefly."),
)
FIELDS = ("version", "outcome", "preflight_us", "inference_us", "delivery_us",
          "cancellation_us", "native_total_us")


def percentile(values: list[float], fraction: float) -> float | None:
    """Nearest-rank quantile; failed trials never masquerade as fast replies."""
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * fraction) - 1)]


def summarize(rows: list[dict]) -> dict:
    success = [row for row in rows if row["status"] == "delivered"]
    def quantiles(field: str) -> dict:
        values = [row[field] for row in success if row.get(field) is not None]
        return {"n": len(values), "p50": statistics.median(values) if values else None,
                "p95": percentile(values, .95)}
    return {
        "attempts": len(rows), "delivered": len(success),
        "failures": {label: sum(row["status"] == label for row in rows)
                     for label in ("admission_rejected", "failed", "timeout", "harness_error")},
        "total_ms": quantiles("total_ms"),
        "preflight_us": quantiles("preflight_us"),
        "inference_us": quantiles("inference_us"),
        "delivery_us": quantiles("delivery_us"),
        "sampled_combined_peak_working_set_bytes": max(
            (row.get("peak_bytes", 0) for row in rows), default=0),
        "incomplete_memory_samples": sum(not row.get("memory_sampling_complete", False) for row in rows),
        "synthetic_quality_passes": sum(row.get("quality_pass") is True for row in rows),
        "synthetic_quality_evaluated": sum(row.get("quality_pass") is not None for row in rows),
    }


def quality_check(label: str, answer: str) -> bool | None:
    # Deliberately narrow heuristics, not a human quality/safety assessment.
    if label == "arithmetic":
        return answer.strip().rstrip(".") == "4"
    if label == "planning":
        return len([line for line in answer.splitlines() if line.strip()]) >= 3
    if label == "uncertainty":
        return any(word in answer.lower() for word in ("cannot", "can't", "no guarantee", "not guarantee"))
    return None


def require_offline() -> None:
    if os.name != "nt":
        raise RuntimeError("windows_required")
    # Read only. Never disconnect the user's network or disrupt a CI runner.
    result = subprocess.run([
        "powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
        "$ErrorActionPreference='Stop'; if (@(Get-NetAdapter | Where-Object Status -eq 'Up').Count) {exit 2}",
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10, check=False)
    if result.returncode != 0:
        raise RuntimeError("offline_condition_not_verified")


def local_metadata(path: str) -> dict:
    # Numeric loopback only, with no env proxies or redirect following.
    # These read-only metadata routes send no conversation text.
    if path not in ("/api/ps", "/api/tags"):
        raise ValueError("unsupported_metadata")
    connection = http.client.HTTPConnection("127.0.0.1", 11434, timeout=2)
    try:
        connection.request("GET", path)
        response = connection.getresponse()
        data = response.read(262145)
        if response.status != 200 or len(data) > 262144:
            raise RuntimeError("invalid_metadata")
        return json.loads(data)
    finally:
        connection.close()


def idle_model_digest() -> str:
    deadline = time.perf_counter() + 10
    while local_metadata("/api/ps").get("models") != []:
        if time.perf_counter() >= deadline:
            raise RuntimeError("model_not_idle")
        time.sleep(.1)
    matches = [model for model in local_metadata("/api/tags").get("models", [])
               if model.get("name") == "qwen3:4b-instruct"]
    if len(matches) != 1 or not re.fullmatch(r"[0-9a-f]{64}", matches[0].get("digest", "")):
        raise RuntimeError("model_digest_not_verified")
    return matches[0]["digest"]


def memory_admission_snapshot() -> dict:
    class Status(ctypes.Structure):
        _fields_ = [("length", wintypes.DWORD), ("load", wintypes.DWORD)] + [
            (name, ctypes.c_uint64) for name in (
                "total", "available", "total_pagefile", "available_pagefile",
                "total_virtual", "available_virtual", "extended")]
    status = Status()
    status.length = ctypes.sizeof(status)
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.GlobalMemoryStatusEx.argtypes = [ctypes.POINTER(Status)]
    kernel.GlobalMemoryStatusEx.restype = wintypes.BOOL
    if not kernel.GlobalMemoryStatusEx(ctypes.byref(status)):
        raise RuntimeError("memory_status_unavailable")
    return {"total_physical_bytes": status.total, "available_physical_bytes": status.available}


class MemorySampler:
    """Sample the foreground trial process plus the local Ollama process tree.

    The 20ms sampled peak is a lower bound, not a kernel/GPU/private-bytes peak.
    No process names, PIDs or command lines are returned or written.
    """
    def __init__(self) -> None:
        class Entry(ctypes.Structure):
            _fields_ = [("size", wintypes.DWORD), ("usage", wintypes.DWORD),
                        ("pid", wintypes.DWORD), ("heap", ctypes.c_size_t),
                        ("module", wintypes.DWORD), ("threads", wintypes.DWORD),
                        ("parent", wintypes.DWORD), ("priority", wintypes.LONG),
                        ("flags", wintypes.DWORD), ("exe", wintypes.WCHAR * 260)]
        class Counters(ctypes.Structure):
            _fields_ = [("size", wintypes.DWORD), ("faults", wintypes.DWORD)] + [
                (name, ctypes.c_size_t) for name in (
                    "peak_working_set", "working_set", "peak_paged", "paged",
                    "peak_nonpaged", "nonpaged", "pagefile", "peak_pagefile")]
        self.Entry, self.Counters = Entry, Counters
        self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        self.psapi = ctypes.WinDLL("psapi", use_last_error=True)
        for name in ("Process32FirstW", "Process32NextW"):
            function = getattr(self.kernel, name)
            function.argtypes = [wintypes.HANDLE, ctypes.POINTER(Entry)]
            function.restype = wintypes.BOOL
        self.kernel.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
        self.kernel.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
        self.kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        self.kernel.OpenProcess.restype = wintypes.HANDLE
        self.kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        self.kernel.CloseHandle.restype = wintypes.BOOL
        self.psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters), wintypes.DWORD]
        self.psapi.GetProcessMemoryInfo.restype = wintypes.BOOL
        self.peak = 0
        self.failed = False
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._run)

    def sample(self) -> int:
        snapshot = self.kernel.CreateToolhelp32Snapshot(2, 0)
        if snapshot == ctypes.c_void_p(-1).value:
            raise RuntimeError("memory_sampling_failed")
        entry = self.Entry()
        entry.size = ctypes.sizeof(entry)
        processes = []
        try:
            more = self.kernel.Process32FirstW(snapshot, ctypes.byref(entry))
            if not more:
                raise RuntimeError("memory_sampling_failed")
            while more:
                processes.append((entry.pid, entry.parent, entry.exe.lower()))
                more = self.kernel.Process32NextW(snapshot, ctypes.byref(entry))
        finally:
            self.kernel.CloseHandle(snapshot)
        selected = {os.getpid()} | {pid for pid, _, name in processes if name.startswith("ollama")}
        while True:
            children = {pid for pid, parent, _ in processes if parent in selected}
            if children <= selected:
                break
            selected |= children
        total = 0
        for pid in selected:
            handle = self.kernel.OpenProcess(0x410, False, pid)
            if not handle:
                # A runner can disappear between enumeration and sampling.
                self.failed = True
                continue
            try:
                counters = self.Counters()
                counters.size = ctypes.sizeof(counters)
                if self.psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.size):
                    total += counters.working_set
                else:
                    self.failed = True
            finally:
                self.kernel.CloseHandle(handle)
        return total

    def _run(self) -> None:
        try:
            while not self.stop.is_set():
                self.peak = max(self.peak, self.sample())
                self.stop.wait(.02)
        except Exception:
            self.failed = True

    def __enter__(self):
        self.peak = self.sample()
        self.thread.start()
        return self

    def __exit__(self, *_):
        self.stop.set()
        self.thread.join(timeout=5)
        if self.thread.is_alive():
            self.failed = True


def trial(dll: Path, fixture: int) -> dict:
    require_offline()
    digest = idle_model_digest()
    library = ctypes.CDLL(str(dll.resolve()), winmode=0x100 | 0x800)
    library.neura_ollama_begin.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    library.neura_ollama_begin.restype = ctypes.c_int64
    library.neura_ollama_poll.argtypes = [ctypes.c_int64, ctypes.c_void_p, ctypes.c_size_t]
    library.neura_ollama_poll.restype = ctypes.c_int
    library.neura_ollama_cancel.argtypes = [ctypes.c_int64]
    library.neura_ollama_cancel.restype = None
    library.neura_ollama_foreground.argtypes = [ctypes.c_int]
    library.neura_ollama_foreground.restype = None
    library.neura_ollama_shutdown.restype = None
    label, question = FIXTURES[fixture]
    request = ctypes.create_string_buffer(json.dumps({
        "system": "You are Neura, a kind, concise companion. Admit uncertainty. Do not claim tool access.",
        "messages": [{"role": "user", "content": question}],
    }).encode())
    reply = ctypes.create_string_buffer(8192)
    record = {"fixture": label, "status": "failed", "quality_pass": None,
              "model_digest": digest, **memory_admission_snapshot()}
    request_id = 0
    try:
        library.neura_ollama_foreground(1)
        with MemorySampler() as memory:
            started = time.perf_counter()
            request_id = library.neura_ollama_begin(request, len(request.raw) - 1)
            if request_id <= 0:
                record["status"] = "admission_rejected"
            else:
                while time.perf_counter() - started < 95:
                    count = library.neura_ollama_poll(request_id, reply, len(reply))
                    if count > 0:
                        record["status"] = "delivered"
                        record["total_ms"] = (time.perf_counter() - started) * 1000
                        answer = reply.raw[:count].decode("utf-8")
                        record["quality_pass"] = quality_check(label, answer)
                        del answer
                        break
                    if count < 0:
                        break
                    time.sleep(.1)  # Identical to the existing Flutter cadence.
                else:
                    record["status"] = "timeout"
                if hasattr(library, "neura_ollama_timing"):
                    function = library.neura_ollama_timing
                    function.argtypes = [ctypes.c_int64, ctypes.POINTER(ctypes.c_uint64), ctypes.c_size_t]
                    function.restype = ctypes.c_int
                    values = (ctypes.c_uint64 * len(FIELDS))()
                    if function(request_id, values, len(values)) == len(values) and values[0] == 1:
                        record.update({key: None if value == 2**64 - 1 else value
                                       for key, value in zip(FIELDS[2:], values[2:])})
            record["attempt_ms"] = (time.perf_counter() - started) * 1000
        record["peak_bytes"] = memory.peak
        record["memory_sampling_complete"] = not memory.failed
    finally:
        if request_id > 0:
            library.neura_ollama_cancel(request_id)
        library.neura_ollama_shutdown()
        ctypes.memset(request, 0, len(request))
        ctypes.memset(reply, 0, len(reply))
    require_offline()
    if idle_model_digest() != digest:
        raise RuntimeError("model_changed_during_trial")
    return record


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--rounds", type=int, choices=range(1, 11), default=10)
    parser.add_argument("--idle-confirmed", action="store_true")
    parser.add_argument("--trial", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--fixture", type=int, choices=range(len(FIXTURES)), default=0, help=argparse.SUPPRESS)
    args = parser.parse_args()
    require_offline()
    if args.trial:
        print(json.dumps(trial(args.trial, args.fixture)))
        return
    if not args.idle_confirmed or not args.baseline or not args.candidate:
        parser.error("Provide both DLLs and --idle-confirmed after closing Neura and all model chats.")
    paths = {"baseline": args.baseline, "candidate": args.candidate}
    hashes = {label: hashlib.sha256(path.read_bytes()).hexdigest() for label, path in paths.items()}
    rows: dict[str, list[dict]] = {label: [] for label in paths}
    # Isolate DLL globals/process memory. Alternate order to reduce order bias.
    for round_number in range(args.rounds):
        for fixture in range(len(FIXTURES)):
            order = ("baseline", "candidate") if round_number % 2 == 0 else ("candidate", "baseline")
            for label in order:
                require_offline()
                try:
                    result = subprocess.run([
                        sys.executable, str(Path(__file__).resolve()),
                        "--trial", str(paths[label].resolve()), "--fixture", str(fixture),
                    ], capture_output=True, timeout=115, check=True)
                    row = json.loads(result.stdout)
                except (subprocess.SubprocessError, ValueError):
                    # Never print the child error stream or private daemon text.
                    row = {"status": "harness_error"}
                rows[label].append(row)
    digests = {row["model_digest"] for data in rows.values() for row in data if "model_digest" in row}
    available = [row["available_physical_bytes"] for data in rows.values() for row in data if "available_physical_bytes" in row]
    conditions_match = (len(digests) == 1 and len(available) == 2 * args.rounds * len(FIXTURES)
                        and max(available) - min(available) <= 128 * 1024**2)
    print(json.dumps({
        "measurement": "opt_in_windows_native_adapter",
        "model": "qwen3:4b-instruct:local", "poll_interval_ms": 100,
        "cold_policy": "keep_alive_0_each_trial_operator_confirmed_initial_idle",
        "binary_sha256": hashes,
        "conditions_match": conditions_match,
        "memory_tolerance_bytes": 128 * 1024**2,
        "summary": {label: summarize(data) for label, data in rows.items()},
        "trials": rows,
        "limitations": ["sampled RAM is a lower bound and excludes GPU memory",
                        "do not compare speed when conditions_match is false or sampling is incomplete",
                        "quality checks are narrow heuristics; human comparison required",
                        "not a Flutter presentation, TTS or actual user laptop acceptance test"],
    }, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print('{"status":"not_measured","reason":"preconditions_or_trial_failed"}')
        sys.exit(1)
