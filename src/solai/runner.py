import subprocess, sys, json, os, importlib
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

# ------------ doctor ----------------------------------------
def _check(cmd: str, name: str):
    try:
        subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT)
        print(f"✓ {name}")
    except subprocess.CalledProcessError as e:
        print(f"✗ {name} not found")
        if "docker build" in cmd:
            print("\nDocker build failed. Check:\n- Network connectivity\n- Docker daemon running\n- Build logs above")
        sys.exit(1)

def _check_python_package(package: str):
    try:
        importlib.import_module(package)
        print(f"✓ {package} importable")
    except ImportError:
        print(f"✗ {package} not installed")
        sys.exit(1)

def image_present(tag: str) -> bool:
    import json, subprocess
    out = subprocess.check_output(f"docker images --format '{{{{json .}}}}' {tag}",
                                  shell=True).decode().strip()
    return bool(out)

def doctor():
    if sys.version_info < (3, 12):
        print("✗ Python 3.12+ required")
        sys.exit(1)

    # Basic CLI tools
    checks = [
        ("pipx --version", "pipx available"),
        ("docker --version", "Docker CLI"),
        ("docker info --format '{{.ServerVersion}}'", "Docker engine running"),
        ("forge --version", "Foundry"),
        ("slither --version", "Slither")
    ]
    for cmd, name in checks:
        _check(cmd, name)

    # Docker image
    img = "foundry_sol"
    tag = "0.4.0"
    if not image_present(f"{img}:{tag}"):
        dockerfile = str(Path(__file__).parent / "docker" / "foundry_sol.Dockerfile")
        try:
            subprocess.run(["docker", "build", "-t", f"{img}:{tag}", "-f", dockerfile, "."], check=True)
        except subprocess.CalledProcessError as e:
            print("\nDocker build failed. Check:\n- Network connectivity\n- Docker daemon running\n- Build logs above")
            sys.exit(1)

    print("🚀  doctor finished – environment ready")

# ------------ backlog runner (placeholder) -------------------
def run_backlog(config_path: Path, once: bool, max_concurrency: int):
    if not config_path.exists():
        print("Config", config_path, "not found"); sys.exit(1)
    
    with ThreadPoolExecutor(max_workers=max_concurrency) as executor:
        print(f"⚙  Starting backlog runner with {max_concurrency} workers")
        if once:
            print("Will exit after backlog drains") 