import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function gpt6Prompt(pi: ExtensionAPI) {
	const promptPath = join(homedir(), ".agents/prompts/gpt-6.2.md");
	pi.on("context_with_system", async ({ messages }, { model }) => {
		if (model?.provider !== "openai" || !model.id.startsWith("gpt-6")) return;
		let prompt: string;
		try {
			prompt = await readFile(promptPath, "utf8");
		} catch (error) {
			if ((error as NodeJS.ErrnoException).code === "ENOENT") return;
			throw error;
		}
		if (!prompt.trim()) return;

		// Append after the leading sections without flattening prompt or tool history.
		const index = messages.findIndex((message) => message.role === "system");
		const system = messages[index];
		if (system?.role !== "system") {
			return { messages: [{ role: "system", content: prompt, timestamp: 0 }, ...messages] };
		}
		return {
			messages: messages.with(index, {
				...system,
				sections: { ...system.sections, "gpt-6.2-prompt": prompt },
			}),
		};
	});
}
