data "external" "registration_token" {
  program = ["bash", "${path.module}/../scripts/get-registration-token.sh"]
  query = {
    repo = var.github_repo
  }
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
# waiter (scripts/wait-for-execution, built on the dedalus-go SDK) so
# `terraform apply` only proceeds once that step actually completed inside
# the guest, and fails the apply on a non-zero remote exit code.
#
# Split into four short steps, rather than one long script, because a single
# long-running exec (observed with `apt-get update` inline) can fail with a
# vsock-level "exceeded timeout grace" transport error independent of
# timeout_ms -- a platform quirk, not a script bug.

resource "dedalus_machine_execution" "download_runner" {
  machine_id = dedalus_machine.runner.machine_id
  command = [
    "bash", "-c",
    templatefile("${path.module}/../scripts/01-download-runner.sh.tftpl", {
      runner_version = var.runner_version
    }),
  ]
  timeout_ms = 60000
}

resource "null_resource" "wait_download_runner" {
  triggers = { execution_id = dedalus_machine_execution.download_runner.execution_id }
  provisioner "local-exec" {
    command     = "go run ."
    working_dir = "${path.module}/../scripts/wait-for-execution"
    environment = {
      DM_MACHINE_ID   = dedalus_machine.runner.machine_id
      DM_EXECUTION_ID = dedalus_machine_execution.download_runner.execution_id
    }
  }
}

resource "dedalus_machine_execution" "install_deps" {
  machine_id = dedalus_machine.runner.machine_id
  command    = ["bash", "-c", file("${path.module}/../scripts/02-install-deps.sh.tftpl")]
  timeout_ms = 240000
  depends_on = [null_resource.wait_download_runner]
}

resource "null_resource" "wait_install_deps" {
  triggers = { execution_id = dedalus_machine_execution.install_deps.execution_id }
  provisioner "local-exec" {
    command     = "go run ."
    working_dir = "${path.module}/../scripts/wait-for-execution"
    environment = {
      DM_MACHINE_ID   = dedalus_machine.runner.machine_id
      DM_EXECUTION_ID = dedalus_machine_execution.install_deps.execution_id
    }
  }
}

resource "dedalus_machine_execution" "configure_runner" {
  machine_id = dedalus_machine.runner.machine_id
  command = [
    "bash", "-c",
    sensitive(templatefile("${path.module}/../scripts/03-configure-runner.sh.tftpl", {
      repo_url    = "https://github.com/${var.github_repo}"
      reg_token   = data.external.registration_token.result.token
      runner_name = var.runner_name
    })),
  ]
  timeout_ms = 60000
  depends_on = [null_resource.wait_install_deps]
}

resource "null_resource" "wait_configure_runner" {
  triggers = { execution_id = dedalus_machine_execution.configure_runner.execution_id }
  provisioner "local-exec" {
    command     = "go run ."
    working_dir = "${path.module}/../scripts/wait-for-execution"
    environment = {
      DM_MACHINE_ID   = dedalus_machine.runner.machine_id
      DM_EXECUTION_ID = dedalus_machine_execution.configure_runner.execution_id
    }
  }
}

resource "dedalus_machine_execution" "start_runner" {
  machine_id = dedalus_machine.runner.machine_id
  command    = ["bash", "-c", file("${path.module}/../scripts/04-start-runner.sh.tftpl")]
  timeout_ms = 30000
  depends_on = [null_resource.wait_configure_runner]
}

resource "null_resource" "wait_start_runner" {
  triggers = { execution_id = dedalus_machine_execution.start_runner.execution_id }
  provisioner "local-exec" {
    command     = "go run ."
    working_dir = "${path.module}/../scripts/wait-for-execution"
    environment = {
      DM_MACHINE_ID   = dedalus_machine.runner.machine_id
      DM_EXECUTION_ID = dedalus_machine_execution.start_runner.execution_id
    }
  }
}
