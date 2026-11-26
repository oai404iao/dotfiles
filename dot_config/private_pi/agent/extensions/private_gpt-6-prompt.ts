import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function gpt6Prompt(pi: ExtensionAPI) {
	const promptPath = join(homedir(), ".agents/prompts/gpt-6.2.md");
	pi.on("before_agent_start", async ({ systemPromptOptions }, { model }) => {
		if (model?.provider !== "openai" || !model.id.startsWith("gpt-6")) return;
		let prompt: string;
		try {
			prompt = await readFile(promptPath, "utf8");
		} catch (error) {
			if ((error as NodeJS.ErrnoException).code === "ENOENT") return;
			throw error;
		}
		if (!prompt.trim()) return;

		const existing = systemPromptOptions.appendSystemPrompt;
		systemPromptOptions.appendSystemPrompt = existing ? `${existing}\n\n${prompt}` : prompt;
	});
}
