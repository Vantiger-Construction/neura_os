"""Verify the portable Windows preview without invoking Ollama or a model.

Checks the extracted package, real Rust ABI and launch self-test. The receipt
explicitly excludes actual model inference and laptop performance validation.
"""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile
import zipfile


EXPORTS = (
    "neura_ollama_begin", "neura_ollama_poll", "neura_ollama_cancel",
    "neura_ollama_foreground", "neura_ollama_block", "neura_ollama_shutdown",
    "neura_ollama_timing", "neura_ollama_clear_timing",
)
REQUIRED = (
    "app/neuro_companion.exe", "app/flutter_windows.dll", "app/neura_swarm.dll",
    "app/neura_api.exe", "app/msvcp140.dll", "app/vcruntime140.dll",
    "app/vcruntime140_1.dll", "app/data/icudtl.dat", "app/data/app.so",
    "app/START_NEURA.bat", "NEURA_OLLAMA_CHAT.md", "PREVIEW_README.txt",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def extract_checked(archive: Path, destination: Path) -> None:
    with zipfile.ZipFile(archive) as package:
        seen: set[str] = set()
        total = 0
        for member in package.infolist():
            name = member.filename.replace("\\", "/")
            path = PurePosixPath(name)
            normalized = str(path).casefold().rstrip("/")
            if (path.is_absolute() or ".." in path.parts or ":" in name
                    or not path.parts or normalized in seen):
                raise ValueError("Unsafe or duplicate preview ZIP entry")
            seen.add(normalized)
            total += member.file_size
            if total > 2 * 1024**3 or len(seen) > 20000:
                raise ValueError("Preview ZIP exceeds extraction bounds")
            target = destination.joinpath(*path.parts)
            if member.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with package.open(member) as source, target.open("wb") as output:
                    while chunk := source.read(1024 * 1024):
                        output.write(chunk)


def check_native_exports(dll: Path) -> None:
    # Match the app owner's restricted DLL search. No PATH/cwd dependency load.
    library = ctypes.CDLL(str(dll), winmode=0x00000100 | 0x00000800)
    for name in EXPORTS:
        getattr(library, name)
    library.neura_ollama_foreground.argtypes = [ctypes.c_int]
    library.neura_ollama_foreground.restype = None
    library.neura_ollama_begin.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    library.neura_ollama_begin.restype = ctypes.c_int64
    library.neura_ollama_block.restype = None
    library.neura_ollama_shutdown.restype = None
    library.neura_ollama_timing.argtypes = [ctypes.c_int64, ctypes.POINTER(ctypes.c_uint64), ctypes.c_size_t]
    library.neura_ollama_timing.restype = ctypes.c_int
    library.neura_ollama_clear_timing.restype = None
    raw = b'{"system":"Synthetic ABI check","messages":[{"role":"user","content":"Hello"}]}'
    buffer = ctypes.create_string_buffer(raw)
    try:
        library.neura_ollama_foreground(0)
        if library.neura_ollama_begin(buffer, len(raw)) != -2:
            raise RuntimeError("Background ABI admission did not fail closed")
        library.neura_ollama_block()
        library.neura_ollama_foreground(1)
        if library.neura_ollama_begin(buffer, len(raw)) != -2:
            raise RuntimeError("Blocked ABI admission did not fail closed")
        timing = (ctypes.c_uint64 * 7)()
        if library.neura_ollama_timing(1, timing, len(timing)) != 0:
            raise RuntimeError("Blocked timing read did not fail closed")
        library.neura_ollama_clear_timing()
    finally:
        library.neura_ollama_shutdown()
        # The test starts no worker. Release before deleting the temporary DLL.
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.FreeLibrary.argtypes = [ctypes.c_void_p]
        kernel.FreeLibrary.restype = ctypes.c_int
        if not kernel.FreeLibrary(library._handle):
            raise ctypes.WinError(ctypes.get_last_error())


def verify(dist: Path, head: str, run_id: str) -> Path:
    if os.name != "nt":
        raise RuntimeError("Real DLL and extracted-app verification requires Windows")
    if not re.fullmatch(r"[0-9a-f]{40}", head):
        raise ValueError("An exact commit SHA is required")
    archives = list(dist.glob("Neura-Ollama-Preview-*.zip"))
    if len(archives) != 1:
        raise ValueError("Expected exactly one preview ZIP")
    archive = archives[0]
    with tempfile.TemporaryDirectory(prefix="neura-ollama-preview-") as temporary:
        root = Path(temporary)
        extract_checked(archive, root)
        for relative in REQUIRED:
            file = root / relative
            if not file.is_file() or file.stat().st_size == 0:
                raise ValueError(f"Missing or empty preview payload: {relative}")
        if not any(file.is_file() for file in (root / "app/data/flutter_assets").rglob("*")):
            raise ValueError("Flutter assets are missing")
        if any(file.stat().st_size == 0 for file in (root / "app").rglob("*.dll")):
            raise ValueError("Extracted preview contains an empty DLL")
        if head not in (root / "PREVIEW_README.txt").read_text(encoding="utf-8-sig"):
            raise ValueError("Preview source label does not match requested head")
        for relative, built in (
            ("app/neura_swarm.dll", Path("rust/target/release/neura_swarm.dll")),
            ("app/neuro_companion.exe", Path("build/windows/x64/runner/Release/neuro_companion.exe")),
        ):
            if sha256(root / relative) != sha256(built):
                raise ValueError(f"Packaged binary differs from this build: {relative}")
        check_native_exports(root / "app/neura_swarm.dll")
        process = subprocess.Popen(
            [str(root / "app/neuro_companion.exe"), "--launch-smoke-test"],
            cwd=root / "app", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        try:
            if process.wait(timeout=15) != 73:
                raise RuntimeError("Extracted app did not return launch sentinel 73")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
        files = [
            {"path": str(file.relative_to(root)).replace("\\", "/"),
             "bytes": file.stat().st_size, "sha256": sha256(file)}
            for file in sorted(root.rglob("*")) if file.is_file()
        ]
    manifest = dist / "OLLAMA_PREVIEW_MANIFEST.json"
    manifest.write_text(json.dumps({
        "source_head": head, "workflow_run_id": run_id,
        "preview": archive.name, "preview_bytes": archive.stat().st_size,
        "preview_sha256": sha256(archive), "files": files,
        "checks": {"runtime_payload": "passed", "rust_ollama_exports": "passed",
                   "background_and_blocked_admission": "passed",
                   "extracted_launch_sentinel_73": "passed"},
        "unverified": ["actual Ollama inference", "installed-app interaction",
                       "laptop peak RAM and response latency", "model conversation quality",
                       "laptop focus/Stop/Safe Mode/recovery/cancellation"],
    }, indent=2) + "\n", encoding="utf-8")
    (dist / "SHA256SUMS.txt").write_text(
        f"{sha256(archive)}  {archive.name}\n{sha256(manifest)}  {manifest.name}\n",
        encoding="utf-8",
    )
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dist", type=Path, required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--run-id", required=True)
    args = parser.parse_args()
    print(verify(args.dist, args.head, args.run_id))

