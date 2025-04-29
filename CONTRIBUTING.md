## Evidence Bundles

The Phase 3 pipeline generates evidence bundles containing test results, logs, and analysis reports. These bundles are crucial for debugging and auditing the pipeline's behavior.

### Location and Contents

Evidence bundles are stored in `.evidence/` and contain:
- `patch.tar`: The generated patch that fixes the failing test
- `slither.txt`: Static analysis results from Slither
- `*.stats`: Per-patch statistics
- `manifest.txt`: List of all included files

### Regenerating Evidence Bundles

To regenerate an evidence bundle locally:

1. Ensure you have all dependencies installed:
   ```bash
   make dev
   ```

2. Run the Phase 3 pipeline:
   ```bash
   ./ci/phase3.sh
   ```

3. The script will:
   - Create a temporary demo repository
   - Run the failing test
   - Generate and apply the patch
   - Run Slither analysis
   - Create the evidence bundle

4. The bundle will be available in `.evidence/` with a timestamp:
   ```bash
   ls -l .evidence/evidence_*.tgz
   ```

### Troubleshooting

If you encounter issues:
1. Check the logs in `.evidence/` for error messages
2. Verify Docker is running (`docker info`)
3. Ensure Foundry is installed (`forge --version`)
4. Check Python dependencies (`pip list`)

For persistent issues, please open an issue with:
- The contents of `.evidence/manifest.txt`
- Relevant error messages
- Your environment details (`uname -a`, `python --version`, etc.)

### Example Evidence Bundle

A sample failed evidence bundle is available at [example-failed-bundle.tgz](https://github.com/your-org/solidity-ai-pipeline/blob/main/docs/example-failed-bundle.tgz). This bundle demonstrates:
- Failed test output
- Slither analysis results
- Patch statistics
- Log files

To examine the bundle:
```bash
# Download and extract
curl -L https://github.com/your-org/solidity-ai-pipeline/raw/main/docs/example-failed-bundle.tgz | tar xz

# View contents
cat .evidence/manifest.txt
``` 