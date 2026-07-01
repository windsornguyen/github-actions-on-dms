import { action, stringInput } from "@dedalus-labs/hollywood";

export const teardownMachine = action({
	name: "Teardown Dedalus Machine",
	description: "Destroy the Dedalus Machine hosting this runner.",
	localActionPath: "dedalus/teardown-machine",
	inputs: {
		machineId: stringInput({ description: "Dedalus machine ID to destroy." }),
		dedalusApiKey: stringInput({ description: "Dedalus API key." }),
		dedalusBaseUrl: stringInput({ description: "Dedalus API base URL." }),
	},
	outputs: {},
	run: async ({ exec, input, log }) => {
		// Destroying the machine kills its own runner process. If that happens
		// synchronously in this step, the runner never gets a chance to report
		// this job's completion back to GitHub, and the workflow run is left
		// stuck "in_progress" forever (confirmed: the destroy succeeded on a
		// prior run, but the run itself never reported success). Delaying the
		// DELETE isn't enough on its own: a plain `&`-backgrounded subshell,
		// even disowned, is still in this step's process group, and the
		// runner kills that whole group the moment the step's own process
		// exits -- confirmed empirically, the backgrounded curl never ran at
		// all. `setsid` starts a genuinely new session, detached from the
		// step's process group entirely, so it survives the step (and the
		// job) finishing.
		log.info(`scheduling destroy of ${input.machineId} in 15s`);
		const script = [
			"setsid bash -c",
			`"sleep 15 && curl -fsSL -X DELETE` +
				` -H 'Authorization: Bearer ${input.dedalusApiKey}'` +
				` -H 'Idempotency-Key: teardown-${input.machineId}-${Date.now()}'` +
				` '${input.dedalusBaseUrl}/v1/machines/${input.machineId}'"`,
			"> /root/teardown.log 2>&1 < /dev/null &",
			"disown",
		].join(" ");
		await exec("bash", ["-c", script]);
		return {};
	},
});
