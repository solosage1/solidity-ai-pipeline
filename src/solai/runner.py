import subprocess, sys, json, os
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

# ------------ doctor ----------------------------------------
def _check(cmd: str, name: str):
    subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT)
    print(f"✓ {name}")

def image_present(tag: str) -> bool:
    import json, subprocess
    out = subprocess.check_output("docker images --format '{{json .}}' "+tag,
                                  shell=True).decode().strip()
    return bool(out)

def doctor():
    if sys.version_info < (3, 12):
        print("✗ Python 3.12+ required")
        sys.exit(1)

    checks = [
        ("docker --version", "Docker CLI"),
        ("docker info --format '{{.ServerVersion}}'", "Docker engine running"),
        ("forge --version", "Foundry"),
        ("slither --version", "Slither"),
        ("sweagent --version", "SWE-Agent"),
        ("swe-rex doctor", "SWE-ReX"),
    ]
    for cmd, name in checks:
        _check(cmd, name)

    img = "foundry_sol:0.4.0"
    if not image_present(img):
        dockerfile = str(Path(__file__).parent / "docker" / "foundry_sol.Dockerfile")
        subprocess.run(["docker", "build", "-t", img, "-f", dockerfile, "."], check=True)

    print("🚀  doctor finished – environment ready")

# ------------ backlog runner (placeholder) -------------------
def run_backlog(config_path: Path, once: bool, max_concurrency: int):
    if not config_path.exists():
        print("Config", config_path, "not found"); sys.exit(1)
    print("⚙  (stub) would load backlog + spawn", max_concurrency, "workers") 