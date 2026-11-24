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
try {
	for (const [id, base, modelId, api, expectedUrl, keyHeader] of [
		["anthropic", anthropicProvider(), "claude-opus-5-5", "anthropic-messages",
			"https://api.commandcode.ai/provider/v1/messages?beta=true", "x-api-key"],
		["google", googleProvider(), "gemini-4-argon", "google-generative-ai",
			"https://www.zzshu.cc/v1beta/models/gemini-4-argon:streamGenerateContent?alt=sse", "x-goog-api-key"],
	]) {
		const provider = composeModelProvider(id, base, config, undefined);
		const model = provider.getModels().find((entry) => entry.id === modelId);
		assert.ok(model, `${id}/${modelId} missing`);
		assert.equal(model.api, api);
		const requests = [];
		const apiKey = "synthetic-provider-key";
		globalThis.fetch = async (input, options) => {
			requests.push(new Request(input, options));
			return new Response(JSON.stringify({
				type: "error", error: { type: "invalid_request_error", message: "synthetic transport capture" },
			}), { status: 400, headers: { "content-type": "application/json" } });
		};
		const result = await provider.streamSimple(model, {
			messages: [{ role: "user", content: [{ type: "text", text: "Offline URL check" }], timestamp: 0 }],
		}, { apiKey, env: {}, maxRetries: 0 }).result();
		assert.equal(requests.length, 1, result.errorMessage);
		const [request] = requests;
		assert.equal(request.url, expectedUrl);
		assert.equal(request.method, "POST");
		assert.equal(request.headers.get(keyHeader), apiKey);
		if (id === "anthropic") assert.equal((await request.json()).model, modelId);
		assert.equal(result.stopReason, "error");
		assert.match(result.errorMessage, /synthetic transport capture/);
	}
} finally {
	globalThis.fetch = originalFetch;
}
console.log("Pi provider URL checks passed (synthetic key, mocked transport)");
