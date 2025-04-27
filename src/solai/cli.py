from pathlib import Path
import importlib.resources as pkg, yaml
import typer
from solai.runner import run_backlog, doctor as run_doctor

app = typer.Typer(help="ℹ  Solidity AI pipeline CLI")


# ----- init --------------------------------------------------
@app.command()
def init(
    update: bool = typer.Option(
        False, "-u", "--update", help="Refresh templates if they already exist"
    ),
):
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

    # Handle gitignore snippet
    gitignore = root / ".gitignore"
    if gitignore.exists():
        content = gitignore.read_text()
        if "# >>> solai" not in content:
            with open(gitignore, "a") as f:
                f.write("\n" + (root / ".gitignore_snip.txt").read_text())
            typer.echo("✓ .gitignore updated with solai patterns")

    typer.echo("✅  Run `make bootstrap-solai`")

    # ---- placeholder digest warning ------------------------------------
    cfg = Path(".solai.yaml")
    if cfg.exists():
        docker_image = yaml.safe_load(cfg.read_text())["env"]["docker_image"]
        if "placeholder_digest" in docker_image:
            typer.secho(
                "⚠  .solai.yaml still has placeholder_digest — "
                "run `solai image-rebuild` and update the file.",
                fg="yellow",
            )


# ----- run ---------------------------------------------------
@app.command()
def run(
    config: Path = Path(".solai.yaml"),
    once: bool = typer.Option(
        False, "--once/--watch", help="Exit after one backlog pass"
    ),
    max_concurrency: int = typer.Option(4),
    log_file: Path = typer.Option(".solai/logs/run.log"),
):
    """Run backlog tasks."""
    run_backlog(config, once, max_concurrency, log_file)


# ----- doctor -----------------------------------------------
@app.command()
def doctor():
    """Environment self-test."""
    run_doctor()


@app.command("image-rebuild")
def image_rebuild():
    """Rebuild & push foundry_sol image, update digest in .solai.yaml."""
    from solai.runner import rebuild_image

    rebuild_image()


if __name__ == "__main__":
    app()
