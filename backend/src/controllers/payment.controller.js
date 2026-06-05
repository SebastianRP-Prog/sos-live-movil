const https = require("https");
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

const mercadoPagoRequest = ({ method = "GET", path, body }) =>
  new Promise((resolve, reject) => {
    const accessToken = process.env.MERCADOPAGO_ACCESS_TOKEN;
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

exports.listCompanies = async (_req, res) => {
  try {
    const snap = await db
      .collection("companies")
      .where("active", "==", true)
      .limit(50)
      .get();

    const companies = snap.docs.map(serializeCompany);
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

    const publicBaseUrl = `${process.env.PUBLIC_BASE_URL ?? ""}`.trim().replace(/\/$/, "");
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
      ...(publicBaseUrl
        ? {
            notification_url: `${publicBaseUrl}/api/auth/payments/mercadopago/webhook`,
            back_urls: {
              success: `${publicBaseUrl}/api/auth/payments/mercadopago/return?status=success`,
              failure: `${publicBaseUrl}/api/auth/payments/mercadopago/return?status=failure`,
              pending: `${publicBaseUrl}/api/auth/payments/mercadopago/return?status=pending`,
            },
            auto_return: "approved",
          }
        : {}),
    };

    const preference = await mercadoPagoRequest({
      method: "POST",
      path: "/checkout/preferences",
      body: preferenceBody,
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

    return res.status(201).json({
      paymentId: paymentRef.id,
      preferenceId: preference.id,
      initPoint: preference.init_point,
      sandboxInitPoint: preference.sandbox_init_point,
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

exports.mercadoPagoWebhook = async (req, res) => {
  try {
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
