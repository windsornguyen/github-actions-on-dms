data "external" "registration_token" {
  program = ["bash", "${path.module}/../scripts/get-registration-token.sh"]
  query = {
    repo = var.github_repo
  }
}

locals {
  boot_script = templatefile("${path.module}/../scripts/gha-runner-boot.sh.tftpl", {
    repo_url       = "https://github.com/${var.github_repo}"
    runner_name    = var.runner_name
    runner_version = var.runner_version
  })
}

resource "dedalus_machine" "runner" {
  vcpu        = 2
  memory_mib  = 4096
  storage_gib = 20
  autosleep   = "never"
}

# dedalus_machine_execution only submits the exec; it does not block until
# the remote command finishes (Create is a single POST, see
# terraform-provider-dedalus/internal/services/machine_execution/resource.go).
# Each step below pairs the resource with a null_resource that runs the Go
# waiter (scripts/wait-for-execution, on the dedalus-go SDK) so `terraform
# apply` only proceeds once that step actually completed inside the guest.
#
# Architecture: sleep/wake is a full guest kernel reboot (confirmed
# empirically -- /proc/uptime resets, tmpfs contents are wiped, dedalusfs
# contents survive). The runner binary lives on a dedicated tmpfs mount
# because extracting its release tarball onto dedalusfs wedges the guest
# (ENG-557) -- but tmpfs doesn't survive reboot either, so the runner must
# fully reinstall on every boot. What DOES persist is the runner's small
# registered identity (.runner/.credentials/.credentials_rsaparams, a few
# KB, well under the ~1MiB write threshold from ENG-561/PLA-177), copied to
# dedalusfs after first registration. A systemd unit re-runs the same boot
# script on every future boot; finding the persisted identity, it skips
# config.sh (and the registration token, which is never needed again)
# entirely and goes straight to serving jobs.

resource "dedalus_machine_execution" "install_boot_script" {
  machine_id = dedalus_machine.runner.machine_id
  command = [
    "bash", "-c",
    "cat > /root/gha-runner-boot.sh <<'BOOTSCRIPT_EOF'\n${local.boot_script}\nBOOTSCRIPT_EOF\nchmod +x /root/gha-runner-boot.sh",
  ]
  timeout_ms = 15000
}

resource "null_resource" "wait_install_boot_script" {
  triggers = { execution_id = dedalus_machine_execution.install_boot_script.execution_id }
  provisioner "local-exec" {
    command     = "go run ."
    working_dir = "${path.module}/../scripts/wait-for-execution"
    environment = {
      DM_MACHINE_ID   = dedalus_machine.runner.machine_id
      DM_EXECUTION_ID = dedalus_machine_execution.install_boot_script.execution_id
    }
  }
}

resource "dedalus_machine_execution" "install_systemd_unit" {
  machine_id = dedalus_machine.runner.machine_id
  command = [
    "bash", "-c",
    "cat > /etc/systemd/system/gha-runner.service <<'UNIT_EOF'\n${file("${path.module}/../scripts/gha-runner.service")}\nUNIT_EOF\nsystemctl daemon-reload\nsystemctl enable gha-runner",
  ]
  timeout_ms = 15000
  depends_on = [null_resource.wait_install_boot_script]
}

resource "null_resource" "wait_install_systemd_unit" {
  triggers = { execution_id = dedalus_machine_execution.install_systemd_unit.execution_id }
  provisioner "local-exec" {
    command     = "go run ."
    working_dir = "${path.module}/../scripts/wait-for-execution"
    environment = {
      DM_MACHINE_ID   = dedalus_machine.runner.machine_id
      DM_EXECUTION_ID = dedalus_machine_execution.install_systemd_unit.execution_id
    }
  }
}

# First-ever bootstrap: runs the same boot script directly with a real
# registration token, backgrounded because it execs into run.sh (a
# long-running process that never returns). Every future boot re-runs this
# script via the enabled systemd unit instead, with no token needed since
# the identity created here is what gets persisted and restored.
resource "dedalus_machine_execution" "first_boot" {
  machine_id = dedalus_machine.runner.machine_id
  command = [
    "bash", "-c",
    sensitive("nohup /root/gha-runner-boot.sh '${data.external.registration_token.result.token}' > /root/boot.log 2>&1 < /dev/null & disown; sleep 1; echo launched"),
  ]
  timeout_ms = 15000
  depends_on = [null_resource.wait_install_systemd_unit]
}

resource "null_resource" "wait_first_boot" {
  triggers = { execution_id = dedalus_machine_execution.first_boot.execution_id }
  provisioner "local-exec" {
    command     = "go run ."
    working_dir = "${path.module}/../scripts/wait-for-execution"
    environment = {
      DM_MACHINE_ID   = dedalus_machine.runner.machine_id
      DM_EXECUTION_ID = dedalus_machine_execution.first_boot.execution_id
    }
  }
}
