import { always, expr, secret, workflow } from "@dedalus-labs/hollywood";

import { teardownMachine } from "./teardown-machine.ts";

export const demoWorkflow = workflow({
	name: "Demo on Dedalus Machine",
	on: {
		workflow_dispatch: {},
		push: { branches: ["main"] },
	},
	jobs: {
		"hello-from-dm": {
			"runs-on": ["self-hosted", "dedalus"],
			steps: [
				{ uses: "actions/checkout@08eba0b27e820071cde6df949e0beb9ba4906955" }, // v4.3.0
				{
					name: "Prove this ran on a Dedalus Machine",
					run: [
						'echo "host: $(hostname)"',
						"uname -a",
						"cat /etc/os-release",
						"mount | grep dedalusfs",
					].join("\n"),
				},
			],
		},
		// Runs on a GitHub-hosted runner, not the DM: a self-hosted runner
		// cannot reliably tear itself down. Destroying the machine kills its
		// own runner process, and that process's cgroup/job supervision
		// kills the *entire* process tree it spawned the instant the job
		// ends -- confirmed empirically that setsid, disown, and a delayed
		// background subshell all still get reaped before ever running.
		// Tearing down from outside the machine being torn down sidesteps
		// the problem entirely instead of fighting the runner's process
		// lifecycle.
		teardown: {
			"runs-on": "ubuntu-latest",
			needs: "hello-from-dm",
			if: always(),
			steps: [
				{ uses: "actions/checkout@08eba0b27e820071cde6df949e0beb9ba4906955" }, // v4.3.0
				{
					name: "Teardown Dedalus Machine",
					uses: `./.github/actions/${teardownMachine.localActionPath}`,
					with: {
						"machine-id": expr("vars.DM_MACHINE_ID"),
						"dedalus-api-key": secret("DEDALUS_API_KEY"),
						"dedalus-base-url": expr("vars.DEDALUS_BASE_URL"),
					},
				},
			],
		},
	},
});
