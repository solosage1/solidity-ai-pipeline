# solai – Solidity AI Pipeline

[![CI](https://github.com/solosage1/solidity-ai-pipeline/actions/workflows/solai.yml/badge.svg)](https://github.com/solosage1/solidity-ai-pipeline/actions/workflows/solai.yml)

> **Plug-and-play pipeline to automatically diagnose & fix failing Solidity tests with GPT-4o-mini, Foundry & Slither.**

---

## ✨ Features

| What | How |
|------|-----|
| **One-command bootstrap** | `make bootstrap-solai` verifies host tools & installs missing Python, Foundry & Slither bits |
| **Agent-powered fixes** | Wraps **SWE-Agent 1.0.1** + **SWE-ReX 1.2.1** – no glue code required |
| **Works everywhere** | Linux, macOS, WSL2; GitHub Actions template included (<span style="color:#268bd2">`.github/workflows/solai-phase3-hello-world.yml`</span>) |
| **Opinionated but hackable** | All behaviour lives in `swe.yaml` (model, cost limits, deployment target) |
| **Doctor & self-heal** | `solai doctor` prints actionable checks + path fixes |

---

## 🔧 Installation

### From PyPI *(coming soon)*

```bash
pip install "solai[ai]"              # installs solai + SWE-Agent + SWE-ReX + Slither
```

### From source (current workflow)

```bash
git clone https://github.com/solosage1/solidity-ai-pipeline.git
cd solidity-ai-pipeline

python -m pip install --upgrade pip build
python -m build                        # ↳ dist/solai-<version>.whl

pip install "dist/solai-*.whl[ai]"     # installs all runtime deps

# verify & set up host
make bootstrap-solai                   # runs `solai doctor` & fixes common issues

# Run the Phase 3 demo script locally (after bootstrap)
./ci/phase3.sh
```

`make bootstrap-solai` will

1. call **`solai doctor`** → checks Python, GPT keys, Docker, Foundry, Slither
2. stub the missing `enterprise.*` modules required by SWE-Agent 1.0.1¹
3. ensure **SWE-Agent CLI is discoverable under *root*** (see *PATH gotchas* below)

<sub>¹ Upstream will remove this quirk in 1.0.2 – until then we create
`site-packages/enterprise/enterprise_hooks/session_handler.py` with no-op
classes.</sub>

---

## 🏃 Quick Start

```bash
# inside an existing Solidity repo
solai init              # adds a default swe.yaml, .gitignore entries, etc.
make bootstrap-solai    # verifies host & prints next steps
solai run --once        # run agent once & exit (CI mode)
```

---

## 📜 Requirements

* **Python 3.12 +** (3.13 works but is still "provisional" for some libs)
* **Foundry >= v1.6.5** – pinned so CI cache never busts

  ```bash
  curl -L https://foundry.paradigm.xyz | bash
  export PATH="$HOME/.foundry/bin:$PATH"
  foundryup
  ```

* **Docker Desktop / engine** – allocate **≥ 6 GB** RAM *(Settings → Resources)*
* **Slither** – pulled in by `solai[ai]`

> **Windows** → use WSL2 - Ubuntu. Native Docker Desktop + Hyper-V is fine too but
> most devs report smoother performance inside WSL2.

---

## 🔑 SWE-ReX / OpenAI keys

| Variable | Purpose | Where |
|----------|---------|-------|
| `OPENAI_API_KEY` | LLM completions (SWE-Agent & ReX) | env / GitHub Secrets |
| `SWE_REX_API_KEY` | authentication to remote ReX service | env / GitHub Secrets |

*HTTP requests* → send header `X-API-Key: $SWE_REX_API_KEY`  
*CLI* → `swerex-remote --api-key $SWE_REX_API_KEY`

---

## 🐞 Troubleshooting & Path gotchas

### 1 · `forge: command not found` under `sudo` (CI)

`foundryup` installs binaries to `$HOME/.foundry/bin`.  The GitHub Action runs
SWE-Agent **as root** to simplify write permissions.  Pre-pend the Foundry dir
in your pipeline **before** calling the agent:

```bash
export PATH="$FOUNDRY_DIR/bin:$PATH"         # FOUNDRY_DIR is /home/runner/.config/.foundry in our template
```

### 2 · `/usr/bin/env: sweagent: No such file or directory`

When you `sudo -E`, root inherits *your* PATH but **not** venv *scripts* dirs.
Add both the *user-site* and *system-site* `…/bin`:

```bash
export PATH="$(python3 -m site --user-base)/bin:$(python3 -c 'import site,sys;print(site.getsitepackages()[0]+"/bin")'):$PATH"
```

(Our workflow already prepends these three segments in one line.)

### 3 · `AssertionError: …/site-packages/config`

SWE-Agent 1.0.1 expects `…/site-packages/config/default.yaml`.  We create a
placeholder automatically during **bootstrap-solai**.  If you installed
manually, run:

```bash
python - <<'PY'
import pathlib, site, textwrap
cfg = pathlib.Path(site.getsitepackages()[0]) / 'config' / 'default.yaml'
cfg.parent.mkdir(parents=True, exist_ok=True)
cfg.write_text(textwrap.dedent('''
agent:
  name: placeholder
'''))
PY
```

### 4 · Enterprise stubs

Until the enterprise hooks land on PyPI run:

```bash
python - <<'PY'
import site, pathlib, textwrap
root = pathlib.Path(site.getsitepackages()[0])
(root/'enterprise').mkdir(exist_ok=True)
(root/'enterprise/__init__.py').write_text('# stub')
(root/'enterprise/enterprise_hooks').mkdir(exist_ok=True)
(root/'enterprise/enterprise_hooks/__init__.py').write_text('# stub')
(root/'enterprise/enterprise_hooks/session_handler.py').write_text('''
class SessionHandler: pass
class ChatCompletionSession: pass
class _ENTERPRISE_ResponsesSessionHandler: pass
''')
PY
```

*(`make bootstrap-solai` already does this)*

---

## 🛠  CI template

A ready-made GitHub Action lives at
`.github/workflows/solai-phase3-hello-world.yml`.
It installs Foundry, caches it by version, pins SWE-Agent/ReX, and runs the
red-green demo (Greeter.sol).  Copy it to your repo & tweak the *Phase 3* step
for your own tests.

---

## 🤝 Contributing & Support

See [CONTRIBUTING.md](CONTRIBUTING.md).  Questions or bug reports → open an
issue or ping @solosage1 on X.

---

© 2024-2025 SoloSage LLC – MIT License
