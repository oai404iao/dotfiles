import assert from "node:assert/strict";
import { realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const piUrl = pathToFileURL(realpathSync(process.argv[2])).href;
const piDist = dirname(fileURLToPath(import.meta.resolve("@earendil-works/pi-coding-agent", piUrl)));
const { ModelConfig } = await import(pathToFileURL(join(piDist, "core/model-config.js")));
const { composeModelProvider } = await import(pathToFileURL(join(piDist, "core/provider-composer.js")));
const { anthropicProvider } = await import(import.meta.resolve("@earendil-works/pi-ai/providers/anthropic", piUrl));
const { googleProvider } = await import(import.meta.resolve("@earendil-works/pi-ai/providers/google", piUrl));
const repo = fileURLToPath(new URL("../", import.meta.url));
const config = await ModelConfig.load(join(repo, "dot_config/private_pi/agent/private_models.json"));
assert.equal(config.getError(), undefined);

const originalFetch = globalThis.fetch;
globalThis.fetch = async () => { throw new Error("Unexpected transport outside mock fetch"); };
try {
	for (const [id, base, modelId] of [
		["anthropic", anthropicProvider(), "claude-opus-5-5"],
		["google", googleProvider(), "gemini-4-argon"],
	]) {
		const provider = composeModelProvider(id, base, config, undefined);
		const model = provider.getModels().find((entry) => entry.id === modelId);
		assert.ok(model, `${id}/${modelId} missing`);
		assert.equal(model.api, "anthropic-messages");
		let calls = 0;
		const result = await provider.streamSimple(model, {
			messages: [{ role: "user", content: [{ type: "text", text: "Offline URL check" }], timestamp: 0 }],
		}, {
			apiKey: "synthetic-zerocat-key",
			env: {},
			maxRetries: 0,
			fetch: async (input, options) => {
				calls++;
				const url = String(input instanceof Request ? input.url : input);
				console.log(`${id}/${modelId} api=${model.api} baseUrl=${model.baseUrl} request=${url}`);
				assert.equal(url, "https://api.zero.cat/v1/messages?beta=true");
				assert.equal(options.method, "POST");
				assert.equal(new Headers(options.headers).get("x-api-key"), "synthetic-zerocat-key");
				assert.equal(JSON.parse(options.body).model, modelId);
				return new Response(JSON.stringify({
					type: "error", error: { type: "invalid_request_error", message: "synthetic transport capture" },
				}), { status: 400, headers: { "content-type": "application/json" } });
			},
		}).result();
		assert.equal(calls, 1);
		assert.equal(result.stopReason, "error");
		assert.match(result.errorMessage, /synthetic transport capture/);
	}
} finally {
	globalThis.fetch = originalFetch;
}
console.log("Pi provider URL checks passed (synthetic key, mocked transport)");
