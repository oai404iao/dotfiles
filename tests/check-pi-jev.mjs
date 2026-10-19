import assert from "node:assert/strict";
import { realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import registerJev from "../dot_config/private_pi/agent/extensions/private_jev.ts";

const piUrl = pathToFileURL(realpathSync(process.argv[2])).href;
const piDist = dirname(fileURLToPath(import.meta.resolve("@earendil-works/pi-coding-agent", piUrl)));
const { ModelConfig } = await import(pathToFileURL(join(piDist, "core/model-config.js")));
const { composeModelProvider } = await import(pathToFileURL(join(piDist, "core/provider-composer.js")));
const { typesafeProvider } = await import(import.meta.resolve("@earendil-works/pi-ai/providers/typesafe", piUrl));
const repo = fileURLToPath(new URL("../", import.meta.url));
const config = await ModelConfig.load(join(repo, "dot_config/private_pi/agent/private_models.json"));
assert.equal(config.getError(), undefined);

let registration;
registerJev({
	registerProvider(id, definition) {
		assert.equal(id, "typesafe");
		assert.equal(registration, undefined);
		registration = definition;
	},
});
const provider = composeModelProvider("typesafe", typesafeProvider(), config, registration);
assert.deepEqual(provider.getModels(), []);
const models = provider.getAllModels();
assert.equal(models.length, 1);
const [jev] = models;
assert.equal(jev.type, "classifier");
assert.equal(jev.id, "typesafe/jev");
assert.equal(jev.api, "typesafe-system-one");
assert.deepEqual(jev.input, ["text"]);
assert.equal(jev.contextWindow, 64000);

const context = {
	state: { task: "Fix a typo in a known file", scope: "one file", risk: "low" },
	questions: {
		workflow: {
			type: "choice",
			instructions: "Choose the smallest useful workflow.",
			criteria: { direct: "Known-path local task", delegate: "Independent work benefits from delegation" },
		},
		review: {
			type: "bool",
			instructions: "Does this need independent review?",
			criteria: { true: "Concrete high risk", false: "Ordinary bounded local change" },
		},
	},
};
const originalFetch = globalThis.fetch;
let calls = 0;
let response;
globalThis.fetch = async (url, options) => {
	calls++;
	assert.equal(String(url), "https://api.commandcode.ai/provider/v1/systemone");
	assert.equal(options.method, "POST");
	assert.equal(new Headers(options.headers).get("Authorization"), "Bearer synthetic-jev-key");
	const body = JSON.parse(options.body);
	assert.equal(body.model, "typesafe/jev");
	assert.deepEqual(body.state, context.state);
	assert.deepEqual(body.questions.workflow, context.questions.workflow);
	assert.deepEqual(body.questions.review, { ...context.questions.review, type: "noul" });
	return response();
};
try {
	response = () => Response.json({
		model: "typesafe/jev",
		answers: {
			workflow: {
				type: "choice", choice: "direct",
				probabilities: { direct: 0.95, delegate: 0.05 }, confidence: 0.9,
			},
			review: { type: "noul", noul: 0.02 },
		},
		usage: { input_tokens: 84, output_tokens: 2 },
	});
	const result = await provider.classify(jev, context, { apiKey: "synthetic-jev-key", maxRetries: 0 });
	assert.equal(result.stopReason, "stop", result.errorMessage);
	assert.equal(result.answers.workflow.choice, "direct");
	assert.deepEqual(result.answers.review, { type: "bool", probability: 0.02 });
	assert.equal(result.usage.totalTokens, 86);

	for (const failure of [
		() => Response.json({ error: { message: "Synthetic unauthorized" } }, { status: 401 }),
		() => Response.json({ answers: {} }),
	]) {
		response = failure;
		const result = await provider.classify(jev, context, { apiKey: "synthetic-jev-key", maxRetries: 0 });
		assert.equal(result.stopReason, "error");
		assert.ok(result.errorMessage);
		assert.deepEqual(result.answers, {});
	}
	assert.equal(calls, 3);
} finally {
	globalThis.fetch = originalFetch;
}
console.log("Pi Jev classifier registration, endpoint, payload, responses, and error checks passed (mock HTTP)");
