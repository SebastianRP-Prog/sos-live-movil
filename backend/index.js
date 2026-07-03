const functions = require("firebase-functions/v1");

const runtimeConfig = functions.config();
process.env.MERCADOPAGO_ACCESS_TOKEN ??=
  runtimeConfig.mercadopago?.access_token;
process.env.MERCADO_PAGO_ACCESS_TOKEN ??=
  runtimeConfig.mercadopago?.access_token;
process.env.PUBLIC_BASE_URL ??= runtimeConfig.mobile?.public_base_url;
process.env.MERCADOPAGO_USE_SANDBOX ??=
  runtimeConfig.mercadopago?.use_sandbox ?? "false";

const app = require("./src/app");

exports.sosMobileApi = functions
  .region("us-central1")
  .runWith({
    maxInstances: 10,
    timeoutSeconds: 60,
    memory: "256MB",
  })
  .https.onRequest(app);
