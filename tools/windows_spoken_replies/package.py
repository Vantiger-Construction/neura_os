"""Package the opt-in Windows launcher with the reviewed Neura release."""

import argparse
import hashlib
import shutil
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

BASE_SHA256 = "2aa6f979300f24a713747da1e370bf2b449b5a741b3a622073314f07f1201355"
HERE = Path(__file__).resolve().parent


def add_file(archive, name, source):
    entry = ZipInfo(name)  # A fixed ZIP timestamp makes repeated builds comparable.
    entry.create_system = 3
    entry.external_attr = 0o100644 << 16
    entry.compress_type = ZIP_DEFLATED
    with archive.open(entry, "w") as dest:
        shutil.copyfileobj(source, dest)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base", type=Path, help="original Windows ZIP from PR 234")
    parser.add_argument("launcher", type=Path, help="compiled Windows x64 launcher")
    parser.add_argument("output", type=Path, help="new spoken-replies ZIP")
    args = parser.parse_args()
    with args.base.open("rb") as base:
        if hashlib.file_digest(base, "sha256").hexdigest() != BASE_SHA256:
            parser.error("the Windows ZIP does not match the reviewed release")
        with ZipFile(base) as app, args.launcher.open("rb") as launcher:
            with args.output.open("xb") as output:
                try:
                    with ZipFile(output, "w") as bundle:
                        add_file(bundle, "START_NEURA.exe", launcher)
                        with (HERE / "START_HERE.txt").open("rb") as guide:
                            add_file(bundle, "START_HERE.txt", guide)
                        for item in app.infolist():
                            name = item.filename.replace("\\", "/")
                            with app.open(item) as src:
                                add_file(bundle, f"Windows/{name}", src)
                        for path in sorted(HERE.iterdir()):
                            if path.suffix in {".go", ".mod", ".sum"} or path.name.endswith("-LICENSE.txt"):
                                with path.open("rb") as src:
                                    add_file(bundle, f"Launcher-source/{path.name}", src)
                except BaseException:
                    output.close()
                    args.output.unlink()
                    raise


if __name__ == "__main__":
    main()
