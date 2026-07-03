const https = require("https");
const crypto = require("crypto");
const { admin, db } = require("../config/firebase");

const normalizeText = (value = "") =>
  `${value}`.trim().toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");

const readToken = (req) => {
  const authHeader = req.headers.authorization || "";
  const [, token] = authHeader.split(" ");
  return token || "";
};

const requireUser = async (req) => {
  const token = readToken(req);
  if (!token) {
    const error = new Error("Token requerido");
    error.status = 401;
    throw error;
  }
  return admin.auth().verifyIdToken(token);
};

const mercadoPagoRequest = ({ method = "GET", path, body, headers = {} }) =>
  new Promise((resolve, reject) => {
    const accessToken =
      process.env.MERCADOPAGO_ACCESS_TOKEN ??
      process.env.MERCADO_PAGO_ACCESS_TOKEN;
    if (!accessToken) {
      const error = new Error("Configura MERCADOPAGO_ACCESS_TOKEN en el backend");
      error.status = 500;
      reject(error);
      return;
    }

    const payload = body ? JSON.stringify(body) : null;
    const request = https.request(
      {
        hostname: "api.mercadopago.com",
        path,
        method,
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
          ...headers,
          ...(payload ? { "Content-Length": Buffer.byteLength(payload) } : {}),
        },
      },
      (response) => {
        let raw = "";
        response.on("data", (chunk) => {
          raw += chunk;
        });
        response.on("end", () => {
          let decoded = {};
          try {
            decoded = raw ? JSON.parse(raw) : {};
          } catch (_) {
            decoded = { raw };
          }

          if (response.statusCode >= 200 && response.statusCode < 300) {
            resolve(decoded);
            return;
          }

          const error = new Error(decoded.message || decoded.error || "Error Mercado Pago");
          error.status = response.statusCode;
          error.detail = decoded;
          reject(error);
        });
      },
    );

    request.on("error", reject);
    if (payload) request.write(payload);
    request.end();
  });

const serializeCompany = (doc) => {
  const data = doc.data();
  return {
    id: doc.id,
    name: data.name ?? data.nombre ?? "Empresa",
    description: data.description ?? data.descripcion ?? "",
    price: Number(data.price ?? data.precio ?? 0),
    currency: data.currency ?? "COP",
    planDays: Number(data.planDays ?? 30),
    agentCount: Number(data.agentCount ?? 0),
  };
};

const companyNameFromData = (data = {}) =>
  `${
    data.name ??
    data.nombre ??
    data.displayName ??
    data.nombreEmpresa ??
    data.nombre_empresa ??
    data.razonSocial ??
    data.razon_social ??
    data.businessName ??
    data.organizationName ??
    data.companyName ??
    data.empresaNombre ??
    data.company?.name ??
    data.company?.nombre ??
    ""
  }`.trim();

const companyPlanFromData = ({ id, name, data = {} }) => ({
  id,
  name,
  description:
    data.description ??
    data.descripcion ??
    "Servicio de seguridad de la empresa",
  price: Number(
    data.price ??
      data.precio ??
      data.companyPrice ??
      data.precioEmpresa ??
      0,
  ),
  currency: data.currency ?? data.moneda ?? "COP",
  planDays: Number(data.planDays ?? data.diasPlan ?? 30),
});

const loadReferencedCompanyIds = async () => {
  const ids = new Set();
  for (const collectionName of ["dashboard_agents", "Agentes"]) {
    const snap = await db.collection(collectionName).limit(500).get();
    for (const doc of snap.docs) {
      const data = doc.data();
      const companyId = `${
        data.companyId ??
        data.empresaId ??
        data.companyUid ??
        data.empresaUid ??
        ""
      }`.trim();
      if (companyId) ids.add(companyId);
    }
  }
  return [...ids];
};

exports.listCompanies = async (_req, res) => {
  try {
    const companiesById = new Map();
    const collectionNames = [
      "companies",
      "empresas",
      "Empresas",
      "dashboard_companies",
      "businesses",
      "organizations",
      "organizaciones",
      "dashboard_users",
      "company_users",
    ];

    for (const collectionName of collectionNames) {
      const snap = await db.collection(collectionName).limit(500).get();
      for (const doc of snap.docs) {
        const data = doc.data();
        if ((data.active ?? data.activa ?? true) === false) continue;
        const name = companyNameFromData(data);
        if (!name) continue;
        companiesById.set(
          doc.id,
          companyPlanFromData({ id: doc.id, name, data }),
        );
      }
    }

    const companyIds = await loadReferencedCompanyIds();
    for (const companyId of companyIds) {
      if (companiesById.has(companyId)) continue;

      let authUser = null;
      try {
        authUser = await admin.auth().getUser(companyId);
      } catch (error) {
        if (error.code !== "auth/user-not-found") throw error;
      }

      const claims = authUser?.customClaims ?? {};
      const authName = `${
        authUser?.displayName ??
        claims.companyName ??
        claims.nombreEmpresa ??
        claims.razonSocial ??
        ""
      }`.trim();
      if (!authName) continue;

      companiesById.set(
        companyId,
        companyPlanFromData({
          id: companyId,
          name: authName,
          data: claims,
        }),
      );
    }

    const companies = [...companiesById.values()].sort((a, b) =>
      a.name.localeCompare(b.name, "es"),
    );
    return res.status(200).json({ companies });
  } catch (error) {
    return res.status(500).json({
      error: "No se pudieron cargar las empresas",
      detail: error.message,
    });
  }
};

exports.companyStatus = async (req, res) => {
  try {
    const decoded = await requireUser(req);
    const userDoc = await db.collection("users").doc(decoded.uid).get();
    const user = userDoc.data() ?? {};

    return res.status(200).json({
      companyId: user.companyId ?? null,
      companyName: user.companyName ?? null,
      companyAccessStatus: user.companyAccessStatus ?? "inactive",
      companyAccessExpiresAt:
        user.companyAccessExpiresAt?.toDate?.()?.toISOString?.() ?? null,
    });
  } catch (error) {
    return res.status(error.status || 500).json({
      error: error.status === 401 ? "Inicia sesion" : "No se pudo consultar el estado",
      detail: error.message,
    });
  }
};

exports.createCompanyPreference = async (req, res) => {
  try {
    const decoded = await requireUser(req);
    const companyId = `${req.body.companyId ?? ""}`.trim();

    if (!companyId) {
      return res.status(400).json({ error: "Empresa requerida" });
    }

    const [userDoc, companyDoc] = await Promise.all([
      db.collection("users").doc(decoded.uid).get(),
      db.collection("companies").doc(companyId).get(),
    ]);

    if (!companyDoc.exists) {
      return res.status(404).json({ error: "La empresa no existe" });
    }

    const company = serializeCompany(companyDoc);
    if (company.price <= 0) {
      return res.status(400).json({ error: "La empresa no tiene precio configurado" });
    }

    const user = userDoc.data() ?? {};
    const paymentRef = db.collection("company_payments").doc();
    await paymentRef.set({
      userId: decoded.uid,
      userEmail: decoded.email ?? user.email ?? "",
      companyId,
      companyName: company.name,
      amount: company.price,
      currency: company.currency,
      status: "pending",
      provider: "mercadopago",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const publicBaseUrl = `${
      process.env.PUBLIC_BASE_URL ??
      process.env.PUBLIC_BACKEND_URL ??
      ""
    }`
      .trim()
      .replace(/\/$/, "");
    const returnBaseUrl = `${process.env.APP_RETURN_BASE_URL ?? "soslive://payments"}`
      .trim()
      .replace(/\/$/, "");
    const preferenceBody = {
      items: [
        {
          id: companyId,
          title: `Acceso SOS LIVE - ${company.name}`,
          description: company.description || `Agentes de ${company.name}`,
          quantity: 1,
          currency_id: company.currency,
          unit_price: company.price,
        },
      ],
      payer: {
        email: decoded.email ?? user.email ?? undefined,
        name: user.name ?? user.nombre ?? undefined,
      },
      external_reference: paymentRef.id,
      metadata: {
        payment_id: paymentRef.id,
        user_id: decoded.uid,
        company_id: companyId,
      },
      back_urls: {
        success: `${returnBaseUrl}/success`,
        failure: `${returnBaseUrl}/failure`,
        pending: `${returnBaseUrl}/pending`,
      },
      auto_return: "approved",
      ...(publicBaseUrl
        ? {
            notification_url: `${publicBaseUrl}/api/auth/payments/mercadopago/webhook`,
          }
        : {}),
    };

    const preference = await mercadoPagoRequest({
      method: "POST",
      path: "/checkout/preferences",
      body: preferenceBody,
      headers: { "X-Idempotency-Key": paymentRef.id },
    });

    await paymentRef.set(
      {
        mpPreferenceId: preference.id,
        initPoint: preference.init_point,
        sandboxInitPoint: preference.sandbox_init_point,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const useSandbox =
      `${process.env.MERCADOPAGO_USE_SANDBOX ?? "true"}`.toLowerCase() === "true";
    const checkoutUrl =
      useSandbox && preference.sandbox_init_point
        ? preference.sandbox_init_point
        : preference.init_point;

    return res.status(201).json({
      paymentId: paymentRef.id,
      preferenceId: preference.id,
      initPoint: preference.init_point,
      sandboxInitPoint: preference.sandbox_init_point,
      checkoutUrl,
    });
  } catch (error) {
    return res.status(error.status || 500).json({
      error: "No se pudo iniciar el pago",
      detail: error.detail ?? error.message,
    });
  }
};

const activateCompanyForPayment = async ({ paymentId, mpPayment }) => {
  const paymentRef = db.collection("company_payments").doc(paymentId);
  const paymentDoc = await paymentRef.get();
  if (!paymentDoc.exists) return;

  const payment = paymentDoc.data();
  const amountMatches =
    Math.abs(Number(mpPayment.transaction_amount) - Number(payment.amount)) < 0.01;
  const currencyMatches =
    `${mpPayment.currency_id ?? ""}`.toUpperCase() ===
    `${payment.currency ?? ""}`.toUpperCase();
  if (!amountMatches || !currencyMatches) {
    await paymentRef.set(
      {
        status: "invalid",
        validationError: "amount_or_currency_mismatch",
        mpPaymentId: `${mpPayment.id ?? ""}`,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return;
  }

  const companyRef = db.collection("companies").doc(payment.companyId);
  const companyDoc = await companyRef.get();
  const company = companyDoc.exists ? serializeCompany(companyDoc) : null;
  const planDays = company?.planDays || 30;
  const expiresAt = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + planDays * 24 * 60 * 60 * 1000),
  );

  const status = mpPayment.status ?? "unknown";
  await paymentRef.set(
    {
      status,
      mpPaymentId: `${mpPayment.id ?? ""}`,
      mpStatusDetail: mpPayment.status_detail ?? null,
      paidAt:
        status === "approved"
          ? admin.firestore.FieldValue.serverTimestamp()
          : payment.paidAt ?? null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      rawPayment: {
        id: mpPayment.id,
        status: mpPayment.status,
        status_detail: mpPayment.status_detail,
        payment_method_id: mpPayment.payment_method_id,
      },
    },
    { merge: true },
  );

  if (normalizeText(status) !== "approved") return;
  if (normalizeText(payment.status) === "approved" && payment.paidAt) return;

  await db.collection("users").doc(payment.userId).set(
    {
      companyId: payment.companyId,
      companyName: payment.companyName,
      companyAccessStatus: "active",
      companyAccessPaymentId: paymentId,
      companyPaidAt: admin.firestore.FieldValue.serverTimestamp(),
      companyAccessExpiresAt: expiresAt,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
};

const validWebhookSignature = (req) => {
  const secret = `${process.env.MERCADOPAGO_WEBHOOK_SECRET ?? ""}`.trim();
  if (!secret) return true;

  const signature = `${req.headers["x-signature"] ?? ""}`;
  const requestId = `${req.headers["x-request-id"] ?? ""}`;
  const dataId = `${
    req.query["data.id"] ?? req.body.data?.id ?? req.query.id ?? ""
  }`.toLowerCase();
  const parts = Object.fromEntries(
    signature.split(",").map((part) => {
      const [key, ...value] = part.trim().split("=");
      return [key, value.join("=")];
    }),
  );
  if (!parts.ts || !parts.v1) return false;

  const manifest = [
    dataId ? `id:${dataId};` : "",
    requestId ? `request-id:${requestId};` : "",
    `ts:${parts.ts};`,
  ].join("");
  const expected = crypto.createHmac("sha256", secret).update(manifest).digest("hex");
  const actualBuffer = Buffer.from(parts.v1, "hex");
  const expectedBuffer = Buffer.from(expected, "hex");
  return (
    actualBuffer.length === expectedBuffer.length &&
    crypto.timingSafeEqual(actualBuffer, expectedBuffer)
  );
};

exports.mercadoPagoWebhook = async (req, res) => {
  try {
    if (!validWebhookSignature(req)) {
      return res.status(401).json({ error: "Firma de webhook invalida" });
    }
    const type = `${req.body.type ?? req.query.type ?? req.query.topic ?? ""}`.trim();
    const paymentId =
      `${req.body.data?.id ?? req.query["data.id"] ?? req.query.id ?? ""}`.trim();

    if (!paymentId || (type && type !== "payment")) {
      return res.status(200).json({ received: true });
    }

    const mpPayment = await mercadoPagoRequest({
      path: `/v1/payments/${encodeURIComponent(paymentId)}`,
    });

    const localPaymentId =
      `${mpPayment.external_reference ?? mpPayment.metadata?.payment_id ?? ""}`.trim();
    if (localPaymentId) {
      await activateCompanyForPayment({ paymentId: localPaymentId, mpPayment });
    }

    return res.status(200).json({ received: true });
  } catch (error) {
    console.error("Mercado Pago webhook error:", error);
    return res.status(200).json({ received: true });
  }
};

exports.mercadoPagoReturn = (_req, res) => {
  res
    .status(200)
    .send("Pago recibido. Puedes volver a SOS LIVE y actualizar tu estado.");
};
