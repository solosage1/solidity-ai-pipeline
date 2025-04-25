from pathlib import Path
import shutil, subprocess, platform, importlib.resources as pkg
import typer
from solai.runner import run_backlog, doctor

app = typer.Typer(help="ℹ  Solidity AI pipeline CLI")

# ----- init --------------------------------------------------
@app.command()
def init(update: bool = typer.Option(False, "-u", "--update",
                                     help="Refresh templates if they already exist")):
    """Inject template files into current repo."""
    root = Path.cwd()
    tdir = pkg.files("solai.templates")
    for tmpl in ["dot_solai.yaml", "Makefile.inc", "gitignore_snip.txt"]:
        tgt = root / tmpl.replace("dot_", ".")
        if tgt.exists() and not update:
            typer.echo(f"• {tgt} exists – skip (use --update to overwrite)")
            continue
        shutil.copy(tdir / tmpl, tgt)
        typer.echo(f"✓ {tgt.relative_to(root)} written")
    typer.echo("✅  Run `make bootstrap-solai`")

# ----- run ---------------------------------------------------
@app.command()
def run(config: Path = Path(".solai.yaml"),
        once: bool = typer.Option(True, help="Exit after backlog drains"),
        max_concurrency: int = typer.Option(4)):
    """Run backlog tasks."""
    run_backlog(config, once, max_concurrency)

# ----- doctor -----------------------------------------------
@app.command()
def doctor():
    """Environment self-test."""
    doctor()

if __name__ == "__main__":
    app() 