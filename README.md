# github-actions-on-dms

GitHub Actions self-hosted runner running on a [Dedalus Machine](https://dedaluslabs.ai), provisioned entirely with the [Dedalus Terraform provider](https://github.com/dedalus-labs/terraform-provider-dedalus). The workflow itself and its teardown action are authored in TypeScript via [`@dedalus-labs/hollywood`](https://oss.dedaluslabs.ai/hollywood), generated and bundled with the `hollywood` CLI — matching how the Dedalus monorepo authors its own GitHub Actions, rather than hand-written YAML.

## How it works

1. `terraform apply` creates one `dedalus_machine` and bootstraps it: writes a boot script and a systemd unit to dedalusfs, then runs the boot script once directly (backgrounded, since it execs into the runner's long-running `run.sh`).
2. **The runner survives sleep/wake.** Confirmed empirically that DCS wake is a full guest kernel reboot — `/proc/uptime` resets, tmpfs is wiped, dedalusfs content survives. The runner binary reinstalls from a tmpfs mount every boot (extracting its release tarball onto dedalusfs wedges the guest — [ENG-557](https://linear.app/dedalus-labs/issue/ENG-557)), but its registered identity (`.runner`/`.credentials`/`.credentials_rsaparams`, a few KB, well under the ~1MiB write threshold from [PLA-177](https://linear.app/dedalus-labs/issue/PLA-177)) persists on dedalusfs. A systemd unit re-runs the boot script on every future boot; finding the persisted identity, it skips registration (and the one-time token) entirely and goes straight to serving jobs.
3. `.github/workflows/demo-workflow.yml` (generated from `ci/demo-workflow.ts`) has two jobs: `hello-from-dm` runs on `[self-hosted, dedalus]` and does the actual work; `teardown` runs on `ubuntu-latest`, `needs: hello-from-dm`, `if: always()`, and destroys the machine via the Dedalus API.
4. Teardown runs on a **separate, GitHub-hosted** runner rather than the DM itself. A self-hosted runner cannot reliably tear itself down: destroying the machine kills its own runner process, and that process's job/cgroup supervision reaps its entire spawned process tree the instant the job ends — confirmed empirically that `setsid`, `disown`, and a delayed background subshell all still got killed before ever running. Tearing down from outside the machine being destroyed sidesteps the problem entirely.

## Prerequisites

- `terraform`, `go`, `gh` (authenticated, with admin access to this repo — used locally at apply time to mint the runner registration token, never stored as a GitHub secret), `jq`, `node`/`npm`.
- `DEDALUS_API_KEY` for `dev.dcs.dedaluslabs.ai`. **Only the dev endpoint works for this demo; prod does not.**

```bash
export DEDALUS_BASE_URL=https://dev.dcs.dedaluslabs.ai
export DEDALUS_API_KEY=<your dev key>
npm install
```

## Usage

```bash
make up          # build + init + apply + verify + demo, in order
```

Or step by step — see `make help` for the full target list (`check-env`, `build`, `init`, `plan`, `apply`, `verify`, `demo`, `destroy`). `apply` is idempotent against an already-bootstrapped machine, but note the machine is **ephemeral per workflow run**: the `teardown` job destroys it after every run, so a second `make demo` needs a fresh `make apply` first.

After changing `ci/*.ts`, regenerate and rebuild before committing:

```bash
npx hollywood generate "ci/**/*.ts" --output . --source-root ci
npx hollywood build
```

Set the GitHub repo variables/secret the teardown action reads (done once per machine by `make apply`'s output, or manually):

```bash
gh variable set DM_MACHINE_ID --body "$(terraform -chdir=terraform output -raw machine_id)"
gh variable set DEDALUS_BASE_URL --body "$DEDALUS_BASE_URL"
gh secret set DEDALUS_API_KEY --body "$DEDALUS_API_KEY"
```

## Known limitations

- **The runner runs from a dedicated 2GiB tmpfs mount (`/mnt/runner-tmpfs`), not the dedalusfs root**, and reinstalls on every boot as a result (see above). Real workloads that fill tmpfs (large checkouts, big toolcaches) can hit its size ceiling — bump `size=2G` in `scripts/gha-runner-boot.sh.tftpl` if needed.
- The `dedalus_machine_execution` resource has no `Update`; changing `command` forces a full replace. Since the registration token is re-minted on every `terraform apply` (external data sources aren't cached), the boot script guards on its own on-disk state (persisted identity, running `Runner.Listener`) so repeated applies are a no-op rather than re-registering.
- Long-running execs (`apt-get update` inline, `systemd-run` used synchronously) have been observed to fail with a vsock transport timeout independent of the exec's own `timeout_ms` — kept each bootstrap step short as a workaround.
- Bug filed during this build, still open: [ENG-561](https://linear.app/dedalus-labs/issue/ENG-561) — sleep can still fail with `HOST_PUBLISH_ERROR` above ~1MiB of unpublished writes despite the linked fix PR being marked done. Kept the persisted identity well under that threshold to avoid it.

## Teardown

Normally automatic (the `teardown` job). To force it manually:

```bash
make destroy
```
