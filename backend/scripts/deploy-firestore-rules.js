const fs = require("fs");
const path = require("path");
const { GoogleAuth } = require("google-auth-library");

const rootDir = path.resolve(__dirname, "..", "..");
const keyPath = path.join(__dirname, "..", "src", "config", "firebase-key.json");
const rulesPath = path.join(rootDir, "firestore.rules");

async function request(url, token, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
      ...(options.headers || {}),
    },
  });

  const body = await response.text();
  if (!response.ok) {
    throw new Error(`${response.status} ${response.statusText}: ${body}`);
  }

  return body ? JSON.parse(body) : null;
}

async function main() {
  const key = JSON.parse(fs.readFileSync(keyPath, "utf8"));
  const content = fs.readFileSync(rulesPath, "utf8");
  const projectId = key.project_id;

  const auth = new GoogleAuth({
    keyFile: keyPath,
    scopes: ["https://www.googleapis.com/auth/cloud-platform"],
  });
  const client = await auth.getClient();
  const token = await client.getAccessToken();
  const accessToken = typeof token === "string" ? token : token.token;

  if (!accessToken) {
    throw new Error("No se pudo obtener access token");
  }

  const ruleset = await request(
    `https://firebaserules.googleapis.com/v1/projects/${projectId}/rulesets`,
    accessToken,
    {
      method: "POST",
      body: JSON.stringify({
        source: {
          files: [
            {
              name: "firestore.rules",
              content,
            },
          ],
        },
      }),
    },
  );

  const releaseName = `projects/${projectId}/releases/cloud.firestore`;
  const release = await request(
    `https://firebaserules.googleapis.com/v1/${releaseName}`,
    accessToken,
    {
      method: "PATCH",
      body: JSON.stringify({
        release: {
          name: releaseName,
          rulesetName: ruleset.name,
        },
        updateMask: "rulesetName",
      }),
    },
  );

  console.log(`Reglas desplegadas: ${release.rulesetName}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
