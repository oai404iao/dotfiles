import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	// models.json adds chat models only; retain TypeSafe's built-in classifier transport.
	pi.registerProvider("typesafe", {
		models: [
			{
				type: "classifier",
				id: "typesafe/jev",
				name: "Jev (Command Code)",
				api: "typesafe-system-one",
				input: ["text"],
				contextWindow: 64000,
				cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
			},
		],
	});
}
