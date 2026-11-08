"""Install verified official archives in an isolated task-specific directory."""
import argparse
import hashlib
import json
import os
import platform
import subprocess
import tarfile
import urllib.request
import zipfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--destination", required=True)
    parser.add_argument("--cache", default=str(ROOT / "_build/toolchain-downloads"))
    args = parser.parse_args()
    lock = json.loads((ROOT / "release/toolchain.lock.json").read_text())
    machine = platform.machine().lower()
    assert machine in ["amd64", "x86_64"], "locked installer currently supports x86_64 only"
    target = "windows-x86_64" if os.name == "nt" else "linux-x86_64"
    assert os.name == "nt" or platform.system() == "Linux", "platform is not in the lock"
    destination, cache = Path(args.destination).resolve(), Path(args.cache).resolve()
    assert destination != Path.home().resolve(), "use an isolated destination"
    marker = destination / ".weft-toolchain.json"
    if destination.exists() and any(destination.iterdir()):
        assert marker.exists() and json.loads(marker.read_text()) == lock, "nonempty destination is not this locked toolchain; choose a new directory"
    else:
        destination.mkdir(parents=True, exist_ok=True)
        cache.mkdir(parents=True, exist_ok=True)
        for key in [target, "core"]:
            archive = lock["archives"][key]
            path = cache / archive["file"]
            if not path.exists():
                print(f"Downloading {key}...", flush=True)
                urllib.request.urlretrieve(archive["url"], path)
            assert digest(path) == archive["sha256"], f"SHA-256 mismatch for {key}; refusing unpinned bytes (refresh the lock explicitly)"
            output = destination / "lib" if key == "core" else destination
            output.mkdir(exist_ok=True)
            if path.suffix == ".zip":
                with zipfile.ZipFile(path) as archive_file:
                    for entry in archive_file.infolist():
                        resolved = (output / entry.filename).resolve()
                        assert resolved.is_relative_to(output), "unsafe archive member"
                    archive_file.extractall(output)
            else:
                with tarfile.open(path) as archive_file:
                    archive_file.extractall(output, filter="data")
        binary = destination / "bin" / ("moon.exe" if os.name == "nt" else "moon")
        env = {**os.environ, "MOON_HOME": str(destination), "PATH": str(destination / "bin") + os.pathsep + os.environ["PATH"]}
        subprocess.run([str(binary), "bundle", "--all"], cwd=destination / "lib/core", env=env, check=True)
        marker.write_text(json.dumps(lock))
    print(f"Toolchain ready at {destination}")
    if os.environ.get("GITHUB_PATH"):
        with open(os.environ["GITHUB_PATH"], "a", encoding="utf-8") as stream:
            stream.write(str(destination / "bin") + "\n")
        with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as stream:
            stream.write("MOON_HOME=" + str(destination) + "\n")

if __name__ == "__main__":
    main()
