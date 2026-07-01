# github-actions-on-dms

GitHub Actions self-hosted runner running on a [Dedalus Machine](https://dedaluslabs.ai), provisioned with the [Dedalus Terraform provider](https://github.com/dedalus-labs/terraform-provider-dedalus).

## How it works

1. `terraform apply` creates one `dedalus_machine` and bootstraps it via `dedalus_machine_execution`.
2. The bootstrap script downloads the GitHub Actions runner, registers it against this repo with the `dedalus` label, and starts it as a systemd unit (`gha-runner`) so it keeps listening for jobs.
3. `.github/workflows/demo.yml` targets `runs-on: [self-hosted, dedalus]` — any push to `main` or manual dispatch runs on the Dedalus Machine.

## Prerequisites

- `gh` CLI authenticated with admin access to this repo (used locally, at apply time, to mint the runner registration token — never stored as a GitHub secret).
- `DEDALUS_API_KEY` for `dev.dcs.dedaluslabs.ai`. **Only the dev endpoint works for this demo; prod does not.**

```bash
export DEDALUS_BASE_URL=https://dev.dcs.dedaluslabs.ai
export DEDALUS_API_KEY=<your dev key>
```

## Usage

```bash
cd terraform
terraform init
terraform apply
```

Check the runner registered:

```bash
gh api repos/windsornguyen/github-actions-on-dms/actions/runners
```

Trigger the demo job:

```bash
gh workflow run demo.yml
gh run watch
```

## Teardown

```bash
cd terraform
terraform destroy
```
