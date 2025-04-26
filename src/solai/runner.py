import subprocess, sys, yaml, shutil, tempfile, platform, re, time, os, contextlib
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

# ── helpers ────────────────────────────────────────────────
def _run(cmd, cwd, log):
    """Run cmd streaming to console & optional log."""
    p = subprocess.Popen(cmd, cwd=cwd, text=True,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    for line in p.stdout:
        print(line, end="")
        if log: log.write(line)
    p.wait()
    if p.returncode:
        raise subprocess.CalledProcessError(p.returncode, cmd)

def image_present(tag: str) -> bool:
    out = subprocess.check_output(
        f"docker images --format '{{{{.Repository}}}}:{{{{.Tag}}}}' {tag}",
        shell=True, text=True).strip()
    return bool(out)

# ── doctor ────────────────────────────────────────────────
def doctor():
    if sys.version_info < (3, 12):
        print("✗ Python 3.12+ required"); sys.exit(1)
    if platform.system() == "Windows":
        print("ℹ  Windows detected – run solai inside WSL2 for best results")

    # Core checks (swe-rex is core, sweagent is not)
    core_checks = [
      ("pipx --version", "pipx available"),
      ("docker --version", "Docker CLI"),
      ("docker info --format '{{.ServerVersion}}'", "Docker engine"),
      ("forge --version", "Foundry"),
      ("slither --version", "Slither"),
      ("swerex-remote --version", "SWE-ReX")
    ]
    for cmd, name in core_checks:
        try:
            subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT)
            print(f"✓ {name}")
        except (subprocess.CalledProcessError, FileNotFoundError):
            print(f"✗ {name} check failed. Please ensure it's installed and in PATH."); sys.exit(1)

    # Optional check for sweagent (needs manual source install)
    try:
        subprocess.check_output("sweagent --version", shell=True, stderr=subprocess.STDOUT)
        print(f"✓ SWE-Agent")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print(f"⚠ SWE-Agent missing. Install from source: git clone https://github.com/princeton-nlp/SWE-agent.git && cd SWE-agent && pip install -e .")

    cfg = Path(".solai.yaml")
    if cfg.exists():
        tag = yaml.safe_load(cfg.read_text())["env"]["docker_image"]
        if not image_present(tag):
            print("✗ Image tag missing – run `solai image-rebuild`"); sys.exit(1)

    print("ℹ  Ensure Docker Desktop memory ≥ 6 GB")
    print("🚀  doctor finished – environment ready")

# ── image rebuild helper ──────────────────────────────────
def rebuild_image():
    img_tag = "foundry_sol:0.4.1"
    here = Path(__file__).parent / "docker" / "foundry_sol.Dockerfile"
    subprocess.run(["docker", "build", "-t", img_tag, "-f", str(here), "."],
                   check=True)
    print("✓ image built:", img_tag)
    print("→ Update .solai.yaml with the new tag")

# ── backlog runner ───────────────────────────────────────
def run_backlog(cfg_path: Path, once: bool, max_conc: int, log_path: Path):
    cfg = yaml.safe_load(cfg_path.read_text())
    model = cfg["agent"]["model"]
    if not re.match(r"[a-z0-9\-]+-\d{4}-\d{2}-\d{2}", model):
        print("Model string must pin date (e.g., gpt4o-2025-04-25)"); return

    def _worker():
        with tempfile.TemporaryDirectory(prefix="solai-") as tmp, \
             open(log_path, "a") as log:
            repo_dir = Path(tmp) / "repo"
            log_path.parent.mkdir(parents=True, exist_ok=True)
            _run(["git", "clone", ".", repo_dir], Path("."), log)
            _run(["git", "-C", repo_dir, "checkout", "-b", cfg["task"]["branch"]],
                 Path("."), log)

            # Write SWE-Agent config
            (repo_dir / "swe.yaml").write_text(f"""
open_pr: false
apply_patch_locally: true
problem_statement:
  repo_path: .
  text: "{cfg['agent']['repo_prompt']}"
env:
  deployment:
    image: {cfg['env']['docker_image']}
""")

            # Run SWE-Agent inside swe-rex
            _run(["swe-rex", "run", "--image", cfg["env"]["docker_image"],
                  "--", "sweagent", "run", "--config", "swe.yaml",
                  "--output-tar", "patch.tar"], repo_dir, log)

            if not (repo_dir / "patch.tar").exists():
                print("No patch produced"); return

            _run(["tar", "-xf", "patch.tar", "-C", "."], repo_dir, log)
            diff_files = list(repo_dir.glob("*.diff")) + list(repo_dir.glob("*.patch"))
            if not diff_files:
                print("No diff inside patch tar"); return
            diff = diff_files[0]

            stat = subprocess.check_output(
                f"git apply --stat {diff}", shell=True, cwd=repo_dir, text=True)
            m = re.search(r'(\d+) insertions?\(\+\), (\d+) deletions?\(-\)', stat)
            ins = int(m.group(1)) if m else 0
            dels = int(m.group(2)) if m else 0
            loc = ins + dels
            if loc == 0 or loc > 2000 or diff.stat().st_size > 100_000:
                print("Patch size invalid"); return

            _run(["git", "apply", str(diff)], repo_dir, log)
            test_res = subprocess.run(["forge", "test", "-q"], cwd=repo_dir)
            if test_res.returncode:
                print("Tests still failing"); return

            print(f"🎉  SWE-Agent applied {loc} LOC; tests green")

    while True:
        with ThreadPoolExecutor(max_workers=max_conc) as pool:
            pool.submit(_worker).result()
        if once:
            break
        time.sleep(30) 