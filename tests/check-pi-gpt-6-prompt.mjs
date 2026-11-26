import assert from "node:assert/strict";
import { existsSync, mkdirSync, readFileSync, realpathSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";

function resolvePiEntry(binPath) {
	const resolved = realpathSync(binPath);
	const agentDir = dirname(dirname(resolved));
	const versionFile = join(agentDir, "install/current-version");
	if (existsSync(versionFile)) {
		const version = readFileSync(versionFile, "utf8").trim();
		const releaseBin = join(agentDir, "install/releases", version, "node_modules/.bin/pi");
		if (existsSync(releaseBin)) return realpathSync(releaseBin);
	}
	return resolved;
}

globalThis.fetch = () => { throw new Error("GPT-6 prompt check must stay offline"); };
const piUrl = pathToFileURL(resolvePiEntry(process.argv[2])).href;
const { createAgentSession, DefaultResourceLoader, ModelRuntime, SessionManager, SettingsManager } =
	await import(import.meta.resolve("@earendil-works/pi-coding-agent", piUrl));
const { getCurrentSystemPrompt, getCurrentTools } =
	await import(import.meta.resolve("@earendil-works/pi-ai", piUrl));
const { fauxProvider, fauxAssistantMessage, fauxToolCall } =
	await import(import.meta.resolve("@earendil-works/pi-ai/providers/faux", piUrl));

const cwd = join(process.argv[3], "prompt-project");
const home = homedir();
assert.equal(home, join(process.argv[3], 'home with "quotes"'));
mkdirSync(cwd);
writeFileSync(join(cwd, "fixture.txt"), "Offline tool input.\n");
const agentDir = join(home, ".config/pi/agent");
const promptPath = join(home, ".agents/prompts/gpt-6.2.md");
const syncedPrompt = readFileSync(promptPath, "utf8");
const modelRuntime = await ModelRuntime.create({
	authPath: join(cwd, "isolated-auth.json"), modelsPath: null,
	modelsStorePath: join(cwd, "isolated-models-store.json"), refreshOnCreate: false,
});
const openai = fauxProvider({ provider: "openai", models: [
	{ id: "gpt-6.2-sol" }, { id: "gpt-6-luna" }, { id: "gpt-5.6-sol" },
] });
const other = fauxProvider({ provider: "fixture", models: [{ id: "gpt-6.2-sol" }] });
modelRuntime.registerNativeProvider(openai.provider);
modelRuntime.registerNativeProvider(other.provider);

let turnSection = "Original companion instructions.";
const settingsManager = SettingsManager.inMemory({ cacheWarming: "off", compaction: { enabled: false } });
const resourceLoader = new DefaultResourceLoader({
	cwd, agentDir, settingsManager,
	extensionFactories: [(pi) => {
		pi.on("before_agent_start", ({ systemPromptOptions }) => {
			systemPromptOptions.sections.companion = turnSection;
		});
	}],
});
await resourceLoader.reload();
const { session } = await createAgentSession({
	cwd, agentDir, modelRuntime, model: openai.getModel(), resourceLoader,
	settingsManager, sessionManager: SessionManager.inMemory(cwd), tools: ["read"],
});

async function checkRequest(provider, userMessage, suffix, toolTurn = false) {
	const requests = [];
	const capture = (reply) => (context) => {
		requests.push({ context, turnPrompt: session.systemPrompt });
		return reply;
	};
	const done = capture(fauxAssistantMessage("Offline response"));
	provider.setResponses(toolTurn ? [
		capture(fauxAssistantMessage(fauxToolCall("read", { path: "fixture.txt" }), { stopReason: "toolUse" })),
		done,
	] : [done]);
	await session.prompt(userMessage);
	assert.equal(requests.length, toolTurn ? 2 : 1);
	assert.equal(session.getLastAssistantText(), "Offline response");
	for (const { context, turnPrompt } of requests) {
		assert.ok(turnPrompt.includes(turnSection));
		assert.equal(getCurrentSystemPrompt(context.messages), turnPrompt + suffix);
		assert.deepEqual(getCurrentTools(context.messages).map((tool) => tool.name), ["read"]);
	}
}

try {
	await session.bindExtensions({});
	await checkRequest(openai, "First request and tool follow-up", `\n\n${syncedPrompt}`, true);
	turnSection = "Changed companion instructions.";
	writeFileSync(promptPath, "Updated while Pi stays open.\n");
	await checkRequest(openai, "Read the updated file", "\n\nUpdated while Pi stays open.\n");
	await session.setModel(openai.getModel("gpt-5.6-sol"));
	await checkRequest(openai, "Same provider, different model family", "");
	await session.setModel(other.getModel());
	await checkRequest(other, "Same model prefix, different provider", "");
	await session.setModel(openai.getModel("gpt-6-luna"));
	await checkRequest(openai, "Switch back to the GPT-6 family", "\n\nUpdated while Pi stays open.\n");
	writeFileSync(promptPath, " \n");
	await checkRequest(openai, "Ignore a blank file", "");
	unlinkSync(promptPath);
	await checkRequest(openai, "Ignore a missing file", "");
} finally {
	session.dispose();
}
console.log("Pi GPT-6 prompt runtime checks passed (Pi SDK, in-process faux providers)");
