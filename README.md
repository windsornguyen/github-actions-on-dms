# github-actions-on-dms

GitHub Actions self-hosted runner running on a [Dedalus Machine](https://dedaluslabs.ai), provisioned entirely with the [Dedalus Terraform provider](https://github.com/dedalus-labs/terraform-provider-dedalus).

## How it works

1. `terraform apply` creates one `dedalus_machine` and bootstraps it in four chained `dedalus_machine_execution` steps: download the runner, install its dependencies, register it against this repo with the `dedalus` label, start it.
2. Each step is paired with a small Go program (`scripts/wait-for-execution`, built on the `dedalus-go` SDK) run as a `local-exec` provisioner. The provider's execution resource only submits the exec — it doesn't block until the remote command finishes — so this fills that gap and makes `terraform apply` fail on a real remote failure instead of reporting success prematurely.
3. `.github/workflows/demo.yml` targets `runs-on: [self-hosted, dedalus]` — any push to `main` or manual dispatch runs on the Dedalus Machine.

## Prerequisites

- `terraform`, `go`, `gh` (authenticated, with admin access to this repo — used locally at apply time to mint the runner registration token, never stored as a GitHub secret), `jq`.
- `DEDALUS_API_KEY` for `dev.dcs.dedaluslabs.ai`. **Only the dev endpoint works for this demo; prod does not.**

```bash
export DEDALUS_BASE_URL=https://dev.dcs.dedaluslabs.ai
export DEDALUS_API_KEY=<your dev key>
```

## Usage

```bash
make up          # build + init + apply + verify + demo, in order
```

Or step by step — see `make help` for the full target list (`check-env`, `build`, `init`, `plan`, `apply`, `verify`, `demo`, `destroy`). `apply` and `verify` are idempotent: re-running against an already-bootstrapped machine is a fast no-op.

## Known limitations

- **The GitHub Actions runner runs from a dedicated 2GiB tmpfs mount (`/mnt/runner-tmpfs`), not the dedalusfs root.** Extracting the runner's release tarball (several hundred files) directly onto dedalusfs wedges the guest badly enough that health checks fail and the platform kills the machine — tracked as [ENG-557](https://linear.app/dedalus-labs/issue/ENG-557). tmpfs is fine for this since the runner install is disposable per-boot, but it's finite RAM-backed storage: the demo job's own checkout/toolcache usage can fill it (`bump size=2G` in `scripts/01-download-runner.sh.tftpl`, or size proportionally to `memory_mib` in `terraform/main.tf`, if you extend the demo workflow to do real work).
- The `dedalus_machine_execution` resource has no `Update`; changing `command` forces a full replace. Since the registration token is re-minted on every `terraform apply` (external data sources aren't cached), every apply would otherwise try to re-run steps that already succeeded — each script guards on its own on-disk state (`.runner` file, `Runner.Listener` process) to make this a no-op.
- Long-running execs (an `apt-get update` inline, `systemd-run`'s D-Bus round-trip) have been observed to fail with a vsock transport timeout independent of the exec's own `timeout_ms`. Kept each bootstrap step short and used plain `nohup`/`disown` instead of `systemd-run` to work around it.

## Teardown

```bash
make destroy
```
