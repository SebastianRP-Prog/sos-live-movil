const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const bundledCredentialsPath = path.join(__dirname, "firebase-key.json");

const loadServiceAccount = () => {
  const explicitCredentialsPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;

  if (explicitCredentialsPath && fs.existsSync(explicitCredentialsPath)) {
    return JSON.parse(fs.readFileSync(explicitCredentialsPath, "utf8"));
  }

  if (fs.existsSync(bundledCredentialsPath)) {
    return JSON.parse(fs.readFileSync(bundledCredentialsPath, "utf8"));
  }

  throw new Error(
    "No se encontro la credencial de Firebase Admin. " +
      "Agrega backend/src/config/firebase-key.json o define GOOGLE_APPLICATION_CREDENTIALS.",
  );
};

admin.initializeApp({
  credential: admin.credential.cert(loadServiceAccount()),
});

const db = admin.firestore();

module.exports = { admin, db };
