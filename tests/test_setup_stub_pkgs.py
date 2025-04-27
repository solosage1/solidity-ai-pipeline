import sys
import subprocess
import pytest
import site
import importlib.util as ilu
from pathlib import Path

# Assume scripts/setup_stub_pkgs.py exists relative to the project root


# Import the functions from setup_stub_pkgs.py
def import_setup_stub_pkgs():
    spec = ilu.spec_from_file_location("setup_stub_pkgs", "scripts/setup_stub_pkgs.py")
    if spec is None or spec.loader is None:
        raise ImportError("Could not load setup_stub_pkgs.py")
    module = ilu.module_from_spec(spec)
    sys.modules["setup_stub_pkgs"] = module  # Add to sys.modules for cleanup
    spec.loader.exec_module(module)
    return module


def test_stub_creation(tmp_path, monkeypatch):
    """Verify setup_stub_pkgs.py creates required dirs and is idempotent."""
    # Import the script's functions
    setup_stub_pkgs = import_setup_stub_pkgs()
    # Ensure cleanup of the imported module
    monkeypatch.addfinalizer(lambda: sys.modules.pop("setup_stub_pkgs", None))

    # Simulate site-packages and sweagent install location
    site_packages_dir = tmp_path / "test_site_packages"
    sweagent_install_dir = site_packages_dir / "sweagent"
    sweagent_install_dir.mkdir(parents=True)
    # Create a dummy __init__.py to simulate the installed package
    (sweagent_install_dir / "__init__.py").touch()

    # Create a mock package directory that's different from site-packages
    pkg_dir = tmp_path / "pkg_dir"
    pkg_dir.mkdir(parents=True)
    (pkg_dir / "sweagent").mkdir(parents=True)
    (pkg_dir / "sweagent" / "__init__.py").touch()

    # Patch site.getsitepackages to return our test dir
    monkeypatch.setattr(site, "getsitepackages", lambda: [str(site_packages_dir)])

    # Patch spec origin to point to our dummy package file and ensure cleanup
    original_find_spec = ilu.find_spec
    monkeypatch.setattr(
        ilu,
        "find_spec",
        lambda name: ilu.spec_from_file_location(
            name, str(pkg_dir / "sweagent" / "__init__.py")
        )
        if name == "sweagent"
        else original_find_spec(name),
    )
    monkeypatch.addfinalizer(lambda: setattr(ilu, "find_spec", original_find_spec))

    # --- First Run ---
    # Run the script's functions directly
    setup_stub_pkgs._ensure_runtime_dirs(site_packages_dir)
    setup_stub_pkgs._ensure_enterprise_stub(site_packages_dir)
    setup_stub_pkgs._ensure_runtime_dirs(pkg_dir)
    setup_stub_pkgs._ensure_enterprise_stub(pkg_dir)

    # Assert directories and key files were created in both locations
    for base_dir in [site_packages_dir, pkg_dir]:
        assert (base_dir / "config").is_dir()
        assert (base_dir / "tools").is_dir()
        assert (base_dir / "trajectories").is_dir()
        assert (base_dir / "enterprise").is_dir()
        assert (base_dir / "enterprise" / "enterprise_hooks").is_dir()
        assert (base_dir / "config" / "__init__.py").exists()
        assert (base_dir / "config" / "default.yaml").exists()
        assert (base_dir / "enterprise" / "__init__.py").exists()
        assert (base_dir / "enterprise" / "enterprise_hooks" / "__init__.py").exists()
        assert (
            base_dir / "enterprise" / "enterprise_hooks" / "session_handler.py"
        ).exists()

        # --- Idempotency Check ---
        # Store file contents before second run
        before = {
            (p.relative_to(base_dir), p.read_bytes())
            for p in base_dir.rglob("*")
            if p.is_file()
        }

        # Run again
        setup_stub_pkgs._ensure_runtime_dirs(base_dir)
        setup_stub_pkgs._ensure_enterprise_stub(base_dir)

        # Store file contents after second run
        after = {
            (p.relative_to(base_dir), p.read_bytes())
            for p in base_dir.rglob("*")
            if p.is_file()
        }

        # Assert contents are identical (idempotency)
        assert before == after, f"Idempotency failed for base_dir: {base_dir}"

    # --- Test main() ---
    # Should run without error now that dirs exist
    try:
        setup_stub_pkgs.main()
    except SystemExit as e:
        pytest.fail(f"setup_stub_pkgs.main() exited unexpectedly: {e}")
    except Exception as e:
        pytest.fail(f"setup_stub_pkgs.main() raised an unexpected exception: {e}")

    # --- Test main() failure case (sweagent not found) ---
    # Temporarily break the find_spec patch
    monkeypatch.setattr(ilu, "find_spec", lambda name: None)
    with pytest.raises(SystemExit) as excinfo:
        setup_stub_pkgs.main()
    assert "sweagent not found" in str(excinfo.value), (
        "main() did not exit as expected when sweagent is missing"
    )

    # Monkeypatch cleanup happens automatically via addfinalizer
