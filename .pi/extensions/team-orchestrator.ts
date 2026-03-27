import { ExtensionAPI } from "@anthropic/pi";

const TEAMS = [
  { name: "VR/WebXR Lead", skill: "vr-webxr", domain: "vr-webxr", tasks: ["V1", "V2", "V3"] },
  { name: "Infrastructure Lead", skill: "k8s-infra", domain: "k8s-infra", tasks: ["K1", "K2", "K3", "K4", "K5"] },
  { name: "Stream Quality Lead", skill: "stream-quality", domain: "stream-quality", tasks: ["S1", "S2", "S3"] },
  { name: "Frontend Lead", skill: "frontend-react", domain: "frontend", tasks: ["F1", "F2", "F3"] },
  { name: "Backend Lead", skill: "backend-express", domain: "backend", tasks: ["B1", "B2", "B3"] },
  { name: "SRE/Monitoring Lead", skill: "sre-monitoring", domain: "sre-monitoring", tasks: ["R1", "R2", "R3"] },
  { name: "QA/Testing Lead", skill: "qa-testing", domain: "qa-testing", tasks: ["Q1", "Q2", "Q3", "Q4"] },
  { name: "Emulation Lead", skill: "qemu-emulation", domain: "emulation", tasks: ["E1", "E2", "E3", "E4"] },
  { name: "Design Lead", skill: "lego-design", domain: "design", tasks: ["D1", "D2", "D3"] },
  { name: "Win98 Computer Use Lead", skill: "win98-computer-use", domain: "win98-image", tasks: ["W1", "W2", "W3", "W4", "W5", "W6"] },
  { name: "LAN Manager Lead", skill: "lan-manager", domain: "lan-networking", tasks: ["L1", "L2", "L3", "L4", "L5", "L6", "L7"] },
];

export default function activate(api: ExtensionAPI) {
  // /team command — list all leads with skills and tasks
  api.registerCommand("team", {
    description: "List all 11 agent team leads with their skills and assigned tasks",
    execute: async () => {
      const lines = [
        "# Lego Loco Cluster — Agent Team Roster",
        "",
        "| # | Lead | Skill | Knowledge Dir | Tasks |",
        "|---|------|-------|--------------|-------|",
      ];
      TEAMS.forEach((t, i) => {
        lines.push(`| ${i + 1} | ${t.name} | \`${t.skill}\` | \`docs/knowledge/${t.domain}/\` | ${t.tasks.join(", ")} |`);
      });
      lines.push("", `**Total**: ${TEAMS.length} leads, ${TEAMS.reduce((a, t) => a + t.tasks.length, 0)} tasks`);
      lines.push("", "Invoke a skill: `/skill:<name>` (e.g., `/skill:win98-computer-use`)");
      return lines.join("\n");
    },
  });

  // /blockers command — aggregate blockers from knowledge base
  api.registerCommand("blockers", {
    description: "Show known blockers across all teams from the knowledge base",
    execute: async (ctx) => {
      const blockerFiles: string[] = [];
      for (const team of TEAMS) {
        const dir = `docs/knowledge/${team.domain}`;
        try {
          const files = await ctx.fs.readdir(dir);
          for (const f of files) {
            if (f.includes("blocker") || f.includes("tracker")) {
              blockerFiles.push(`${dir}/${f}`);
            }
          }
        } catch {
          // Directory may not exist or be empty
        }
      }

      if (blockerFiles.length === 0) {
        return "No blocker documents found in knowledge base. Check `docs/knowledge/lan-networking/lan-blockers-tracker.md` once created (Task L1).";
      }

      const lines = ["# Known Blockers", ""];
      for (const file of blockerFiles) {
        try {
          const content = await ctx.fs.readFile(file, "utf-8");
          lines.push(`## ${file}`, "", content, "---", "");
        } catch {
          lines.push(`## ${file}`, "", "*Could not read file*", "---", "");
        }
      }
      return lines.join("\n");
    },
  });

  // /knowledge command — show latest entries from a domain
  api.registerCommand("knowledge", {
    description: "Show latest knowledge entries for a domain (e.g., /knowledge lan-networking)",
    execute: async (ctx, args) => {
      const domain = args?.trim();
      if (!domain) {
        return `Usage: /knowledge <domain>\n\nDomains: ${TEAMS.map(t => t.domain).join(", ")}`;
      }

      const dir = `docs/knowledge/${domain}`;
      try {
        const files = await ctx.fs.readdir(dir);
        const mdFiles = files.filter((f: string) => f.endsWith(".md")).sort().reverse();

        if (mdFiles.length === 0) {
          return `No knowledge entries found in \`${dir}/\`. Start documenting!`;
        }

        const lines = [`# Knowledge: ${domain}`, "", `**${mdFiles.length} entries**`, ""];
        // Show latest 5
        for (const f of mdFiles.slice(0, 5)) {
          try {
            const content = await ctx.fs.readFile(`${dir}/${f}`, "utf-8");
            const firstLines = content.split("\n").slice(0, 10).join("\n");
            lines.push(`## ${f}`, "", firstLines, "", "---", "");
          } catch {
            lines.push(`## ${f}`, "*Could not read*", "");
          }
        }
        return lines.join("\n");
      } catch {
        return `Domain \`${domain}\` not found. Valid: ${TEAMS.map(t => t.domain).join(", ")}`;
      }
    },
  });

  // Session start event — show team summary
  api.on("session_start", () => {
    console.log(`🧱 Lego Loco Cluster — ${TEAMS.length} agent teams loaded`);
    console.log(`   Skills: ${TEAMS.map(t => t.skill).join(", ")}`);
    console.log(`   Commands: /team, /blockers, /knowledge <domain>`);
  });
}
