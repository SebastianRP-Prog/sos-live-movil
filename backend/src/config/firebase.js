const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

const keyPath = path.join(__dirname, "firebase-key.json");

let credential = admin.credential.applicationDefault();

if (fs.existsSync(keyPath)) {
  credential = admin.credential.cert(require(keyPath));
} else if (process.env.FIREBASE_SERVICE_ACCOUNT) {
  credential = admin.credential.cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT));
} else {
  console.warn(
    "Firebase service account not found. Using application default credentials."
  );
}

admin.initializeApp({ credential });

const db = admin.firestore();

module.exports = { admin, db };
