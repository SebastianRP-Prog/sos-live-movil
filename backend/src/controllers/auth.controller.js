const { admin, db } = require("../config/firebase");

const GMAIL_REGEX = /^[^\s@]+@gmail\.com$/i;
const PHONE_REGEX = /^\d{10,15}$/;
const PASSWORD_REGEX = /^(?=.*[A-Za-z])(?=.*\d).{8,}$/;

const normalizeEmail = (value = "") => value.trim().toLowerCase();
const normalizePhone = (value = "") => value.replace(/\D/g, "");
const normalizeText = (value = "") =>
  `${value}`.trim().toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");

const DUPLICATE_SOS_RADIUS_METERS = 25;

const readNumber = (value) => {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
};

const distanceMeters = (lat1, lng1, lat2, lng2) => {
  const toRadians = (degrees) => (degrees * Math.PI) / 180;
  const earthRadiusMeters = 6371000;
  const dLat = toRadians(lat2 - lat1);
  const dLng = toRadians(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  return earthRadiusMeters * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
};

const hasOpenStatus = (data) => {
  const status = normalizeText(data.status ?? data.estado ?? "active");
  return status !== "closed" && status !== "cerrada" && status !== "cerrado";
};

const findAgentCompanyId = async ({ agentName, agentId }) => {
  const normalizedAgentName = normalizeText(agentName);
  const idsToTry = [
    `${agentId ?? ""}`.trim(),
    `${agentName ?? ""}`.trim(),
  ].filter(Boolean);

  const collections = ["dashboard_agents", "Agentes"];
  for (const collectionName of collections) {
    for (const id of idsToTry) {
      const doc = await db.collection(collectionName).doc(id).get();
      if (doc.exists) {
        const data = doc.data();
        const companyId = `${data.companyId ?? data.empresaId ?? ""}`.trim();
        if (companyId) return companyId;
      }
    }

    if (normalizedAgentName) {
      const snap = await db.collection(collectionName).limit(100).get();
      for (const doc of snap.docs) {
        const data = doc.data();
        const name = `${data.nombre ?? data.name ?? ""}`.trim();
        if (normalizeText(name) === normalizedAgentName) {
          const companyId = `${data.companyId ?? data.empresaId ?? ""}`.trim();
          if (companyId) return companyId;
        }
      }
    }
  }

  return "";
};

const findDuplicateSosAtLocation = async ({ uid, lat, lng }) => {
  const snap = await db
    .collection("dashboard_alerts")
    .where("userId", "==", uid)
    .limit(30)
    .get();

  for (const doc of snap.docs) {
    const data = doc.data();
    if (!hasOpenStatus(data)) continue;

    const existingLat = readNumber(data.lat ?? data.location?.lat);
    const existingLng = readNumber(data.lng ?? data.location?.lng);
    if (existingLat == null || existingLng == null) continue;

    const distance = distanceMeters(lat, lng, existingLat, existingLng);
    if (distance <= DUPLICATE_SOS_RADIUS_METERS) {
      return doc.id;
    }
  }

  return null;
};

const mapRegisterError = (error) => {
  switch (error.code) {
    case "auth/email-already-exists":
      return { status: 400, message: "El correo Gmail ya esta registrado" };
    case "auth/invalid-email":
      return { status: 400, message: "Ingresa un correo Gmail valido" };
    case "auth/invalid-password":
      return {
        status: 400,
        message: "La contrasena debe tener minimo 8 caracteres",
      };
    default:
      return {
        status: 500,
        message: "No se pudo registrar el usuario",
      };
  }
};

exports.register = async (req, res) => {
  let createdUser = null;

  try {
    const email = normalizeEmail(req.body.email);
    const phone = normalizePhone(req.body.phone);
    const password = `${req.body.password ?? ""}`.trim();
    const name = `${req.body.name ?? req.body.nombre ?? ""}`.trim();
    const age = Number.parseInt(req.body.age ?? req.body.edad, 10);
    const gender = `${req.body.gender ?? req.body.sexo ?? ""}`.trim();
    const bloodType = `${
      req.body.bloodType ?? req.body.tipoSangre ?? ""
    }`.trim();

    if (!email || !password || !name || !gender || !bloodType) {
      return res.status(400).json({ error: "Completa todos los campos" });
    }

    if (!Number.isInteger(age) || age <= 0 || age > 120) {
      return res.status(400).json({ error: "Ingresa una edad valida" });
    }

    if (!GMAIL_REGEX.test(email)) {
      return res
        .status(400)
        .json({ error: "Ingresa un correo Gmail valido" });
    }

    if (phone && !PHONE_REGEX.test(phone)) {
      return res.status(400).json({
        error: "El telefono debe tener entre 10 y 15 digitos",
      });
    }

    if (!PASSWORD_REGEX.test(password)) {
      return res.status(400).json({
        error: "La contrasena debe tener minimo 8 caracteres, letras y numeros",
      });
    }

    if (phone) {
      const existingPhone = await db
        .collection("users")
        .where("phone", "==", phone)
        .limit(1)
        .get();

      if (!existingPhone.empty) {
        return res
          .status(400)
          .json({ error: "El telefono ya esta registrado" });
      }
    }

    createdUser = await admin.auth().createUser({
      email,
      password,
    });

    await db.collection("users").doc(createdUser.uid).set({
      name,
      email,
      age,
      gender,
      bloodType,
      role: "persona",
      type: "persona",
      guardians: [],
      ...(phone ? { phone } : {}),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return res.status(201).json({
      message: "Usuario registrado correctamente",
      uid: createdUser.uid,
    });
  } catch (error) {
    if (createdUser?.uid) {
      try {
        await admin.auth().deleteUser(createdUser.uid);
      } catch (_) {
        // Ignore cleanup failures and return the original error.
      }
    }

    const mappedError = mapRegisterError(error);
    return res.status(mappedError.status).json({ error: mappedError.message });
  }
};


exports.login = async (req, res) => {
  res.status(400).json({ error: "Login ahora se maneja con Firebase" });
};

exports.loginAgent = async (req, res) => {
  try {
    const name = `${req.body.name ?? req.body.nombre ?? ""}`.trim();
    const code = `${req.body.code ?? req.body.codigo ?? ""}`.trim();

    if (!name || !code) {
      return res.status(400).json({ error: "Completa nombre y codigo" });
    }

    const attempts = [
      { codeField: "codigo", nameField: "nombre" },
      { codeField: "codigo", nameField: "name" },
      { codeField: "code", nameField: "nombre" },
      { codeField: "code", nameField: "name" },
    ];

    const collections = ["dashboard_agents", "Agentes"];

    for (const collectionName of collections) {
      for (const attempt of attempts) {
        const snap = await db
          .collection(collectionName)
          .where(attempt.codeField, "==", code)
          .limit(20)
          .get();

        for (const doc of snap.docs) {
          const data = doc.data();
          const agentName = `${data[attempt.nameField] ?? ""}`.trim();

          if (normalizeText(agentName) === normalizeText(name)) {
            const authUid = `${data.authUid ?? data.firebaseUid ?? data.uid ?? data.agentId ?? doc.id}`.trim();
            const chatAgentId = `${data.codigo ?? data.code ?? code ?? authUid}`.trim();
            const customToken = await admin.auth().createCustomToken(authUid, {
              role: "agent",
              agentDocId: doc.id,
            });

            return res.status(200).json({
              id: doc.id,
              ...data,
              uid: chatAgentId,
              authUid,
              agentId: chatAgentId,
              customToken,
              nombre: data.nombre ?? data.name ?? agentName,
              name: data.name ?? data.nombre ?? agentName,
              codigo: data.codigo ?? data.code ?? code,
              code: data.code ?? data.codigo ?? code,
            });
          }
        }
      }
    }

    return res.status(401).json({ error: "Nombre o codigo incorrectos" });
  } catch (error) {
    return res.status(500).json({
      error: "No se pudo validar el agente",
      detail: error.message,
    });
  }
};

exports.saveProfile = async (req, res) => {
  try {
    const authHeader = req.headers.authorization || "";
    const [, token] = authHeader.split(" ");
    let decodedToken = null;

    if (token) {
      try {
        decodedToken = await admin.auth().verifyIdToken(token);
      } catch (error) {
        console.warn("No se pudo verificar el token:", error.message);
      }
    }

    const uid = decodedToken?.uid || `${req.body.uid ?? ""}`.trim();
    const email = normalizeEmail(decodedToken?.email || req.body.email);
    const name = `${req.body.name ?? req.body.nombre ?? ""}`.trim();
    const age = Number.parseInt(req.body.age ?? req.body.edad, 10);
    const gender = `${req.body.gender ?? req.body.sexo ?? ""}`.trim();
    const bloodType = `${
      req.body.bloodType ?? req.body.tipoSangre ?? ""
    }`.trim();

    if (!uid || !email || !name || !gender || !bloodType) {
      return res.status(400).json({ error: "Completa todos los campos" });
    }

    if (!Number.isInteger(age) || age <= 0 || age > 120) {
      return res.status(400).json({ error: "Ingresa una edad valida" });
    }

    await db.collection("users").doc(uid).set(
      {
        name,
        email,
        age,
        gender,
        bloodType,
        role: "persona",
        type: "persona",
        guardians: [],
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return res.status(200).json({
      message: "Perfil guardado correctamente",
      uid,
    });
  } catch (error) {
    return res.status(500).json({
      error: "No se pudo guardar el perfil",
      detail: error.message,
    });
  }
};

exports.saveDashboardAlert = async (req, res) => {
  try {
    const authHeader = req.headers.authorization || "";
    const [, token] = authHeader.split(" ");
    let decodedToken = null;

    if (token) {
      try {
        decodedToken = await admin.auth().verifyIdToken(token);
      } catch (error) {
        console.warn("No se pudo verificar token de alerta:", error.message);
      }
    }

    const uid = decodedToken?.uid || `${req.body.uid ?? ""}`.trim();
    const userEmail = normalizeEmail(decodedToken?.email || req.body.userEmail);
    const userName = `${req.body.userName ?? req.body.name ?? ""}`.trim();
    const lat = Number(req.body.lat);
    const lng = Number(req.body.lng);
    const mapUrl =
      `${req.body.mapUrl ?? ""}`.trim() ||
      `https://www.google.com/maps/search/?api=1&query=${lat},${lng}`;
    const guardianIds = Array.isArray(req.body.guardianIds)
      ? req.body.guardianIds.filter((id) => typeof id === "string")
      : [];
    let userCompany = {};

    if (!uid || !Number.isFinite(lat) || !Number.isFinite(lng)) {
      return res.status(400).json({ error: "Datos de alerta incompletos" });
    }

    try {
      const userDoc = await db.collection("users").doc(uid).get();
      const user = userDoc.data() ?? {};
      if (normalizeText(user.companyAccessStatus) === "active" && user.companyId) {
        userCompany = {
          companyId: user.companyId,
          companyName: user.companyName ?? "",
        };
      }
    } catch (_) {
      userCompany = {};
    }

    const duplicateAlertId = await findDuplicateSosAtLocation({ uid, lat, lng });
    if (duplicateAlertId) {
      return res.status(409).json({
        error: "Ya existe una alerta activa en esta ubicacion",
        duplicateAlertId,
      });
    }

    const alertData = {
      type: "sos",
      status: "active",
      estado: "active",
      priority: "high",
      prioridad: "Alta",
      title: "SOS Activado",
      message: `${userName || userEmail || uid} activo una alerta de emergencia`,
      persona: userName || userEmail || "Usuario SOS",
      correoPersona: userEmail,
      ubicacion: `lat ${lat}, lng ${lng}`,
      mapUrl,
      userId: uid,
      userName: userName || userEmail || "Usuario SOS",
      userEmail,
      guardianIds,
      ...userCompany,
      agenteAsignado: "Sin asignar",
      location: { lat, lng },
      ubicacionActiva: {
        lat,
        lng,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      lat,
      lng,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      source: "mobile_app",
    };

    const activeAlertData = {
      nombrePersona: alertData.persona,
      persona: alertData.persona,
      correoPersona: alertData.correoPersona,
      ubicacionActiva: {
        lat,
        lng,
      },
      ubicacion: alertData.ubicacion,
      lat,
      lng,
      fechaHora: admin.firestore.FieldValue.serverTimestamp(),
      fecha: admin.firestore.FieldValue.serverTimestamp(),
      hora: new Date().toLocaleTimeString("es-CO", {
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
        hour12: true,
        timeZone: "America/Bogota",
      }),
      estado: "active",
      status: "active",
      agenteAsignado: "Sin asignar",
      ...userCompany,
      dashboardAlertId: null,
      source: "mobile_app",
    };

    const dashboardAlertRef = db.collection("dashboard_alerts").doc();
    const sosAlertRef = db.collection("sos_alerts").doc(dashboardAlertRef.id);
    const activeAlertRef = db
      .collection("alertas_activas")
      .doc(dashboardAlertRef.id);
    const batch = db.batch();
    batch.set(dashboardAlertRef, alertData);
    batch.set(sosAlertRef, {
      ...alertData,
      dashboardAlertId: dashboardAlertRef.id,
    });
    batch.set(activeAlertRef, {
      ...activeAlertData,
      dashboardAlertId: dashboardAlertRef.id,
    });
    await batch.commit();

    return res.status(201).json({
      message: "Alerta creada correctamente",
      id: dashboardAlertRef.id,
      sosAlertId: sosAlertRef.id,
      activeAlertId: activeAlertRef.id,
    });
  } catch (error) {
    return res.status(500).json({
      error: "No se pudo crear la alerta del dashboard",
      detail: error.message,
    });
  }
};

const isUnassignedAlert = (data) => {
  const assigned = `${data.agenteAsignado ?? ""}`.trim();
  return !assigned || normalizeText(assigned) === "sin asignar";
};

exports.listDashboardAlerts = async (req, res) => {
  try {
    const agentName = `${req.query.agentName ?? req.query.nombre ?? ""}`.trim();
    const agentId = `${req.query.agentId ?? req.query.uid ?? ""}`.trim();
    const normalizedAgentName = normalizeText(agentName);
    const agentCompanyId =
      `${req.query.companyId ?? ""}`.trim() ||
      (await findAgentCompanyId({ agentName, agentId }));
    const snap = await db
      .collection("dashboard_alerts")
      .orderBy("createdAt", "desc")
      .limit(50)
      .get();

    const alerts = snap.docs
      .map((doc) => {
        const data = doc.data();
        return {
          id: doc.id,
          ...data,
          createdAt: data.createdAt?.toDate?.()?.toISOString?.() ?? null,
          updatedAt: data.updatedAt?.toDate?.()?.toISOString?.() ?? null,
        };
      })
      .filter((alert) => {
        const status = normalizeText(alert.status ?? alert.estado ?? "active");
        const assigned = normalizeText(alert.agenteAsignado ?? alert.acceptedBy);
        const assignedToThisAgent =
          normalizedAgentName && assigned === normalizedAgentName;
        const alertCompanyId = `${alert.companyId ?? ""}`.trim();

        if (status === "closed" || status === "cerrada" || status === "cerrado") {
          return false;
        }

        if (alertCompanyId && agentCompanyId && alertCompanyId !== agentCompanyId) {
          return false;
        }

        if (alertCompanyId && !agentCompanyId) {
          return false;
        }

        if (status === "accepted" || status === "aceptada" || status === "aceptado") {
          return assignedToThisAgent;
        }

        return isUnassignedAlert(alert);
      });

    return res.status(200).json({ alerts });
  } catch (error) {
    return res.status(500).json({
      error: "No se pudieron cargar las alertas",
      detail: error.message,
    });
  }
};

exports.acceptDashboardAlert = async (req, res) => {
  try {
    const alertId = `${req.params.alertId ?? ""}`.trim();
    const agentName = `${req.body.agentName ?? req.body.nombre ?? ""}`.trim();
    const agentId = `${req.body.agentId ?? req.body.agentUid ?? req.body.uid ?? ""}`.trim();
    const agentCompanyId =
      `${req.body.companyId ?? ""}`.trim() ||
      (await findAgentCompanyId({ agentName, agentId }));

    if (!alertId) {
      return res.status(400).json({ error: "Alerta invalida" });
    }

    if (!agentName) {
      return res.status(400).json({ error: "Agente invalido" });
    }

    const alertRef = db.collection("dashboard_alerts").doc(alertId);
    const result = await db.runTransaction(async (transaction) => {
      const doc = await transaction.get(alertRef);
      if (!doc.exists) {
        return { status: 404, error: "La alerta no existe" };
      }

      const data = doc.data();
      const status = normalizeText(data.status ?? data.estado ?? "active");
      const assigned = normalizeText(data.agenteAsignado ?? data.acceptedBy);
      const normalizedAgentName = normalizeText(agentName);
      const alertCompanyId = `${data.companyId ?? ""}`.trim();

      if (status === "closed" || status === "cerrada" || status === "cerrado") {
        return { status: 409, error: "La alerta ya fue cerrada" };
      }

      if (alertCompanyId && !agentCompanyId) {
        return { status: 403, error: "Esta alerta requiere empresa asignada" };
      }

      if (alertCompanyId && agentCompanyId && alertCompanyId !== agentCompanyId) {
        return { status: 403, error: "Esta alerta pertenece a otra empresa" };
      }

      if (
        (status === "accepted" || status === "aceptada" || status === "aceptado") &&
        assigned &&
        assigned !== normalizedAgentName
      ) {
        return { status: 409, error: "Esta alerta ya fue aceptada por otro agente" };
      }

      if (!isUnassignedAlert(data) && assigned && assigned !== normalizedAgentName) {
        return { status: 409, error: "Esta alerta ya fue aceptada por otro agente" };
      }

      const update = {
        status: "accepted",
        estado: "accepted",
        agenteAsignado: agentName,
        acceptedBy: agentName,
        ...(agentId
          ? {
              agentId,
              agentUid: agentId,
              acceptedById: agentId,
              guardianId: agentId,
            }
          : {}),
        acceptedAt: data.acceptedAt ?? admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      transaction.set(alertRef, update, { merge: true });
      return { status: 200, update };
    });

    if (result.status !== 200) {
      return res.status(result.status).json({ error: result.error });
    }

    const update = result.update;

    await db.collection("sos_alerts").doc(alertId).set(update, {
      merge: true,
    });

    await db.collection("alertas_activas").doc(alertId).set(update, {
      merge: true,
    });

    return res.status(200).json({
      message: "Alerta aceptada correctamente",
      id: alertId,
    });
  } catch (error) {
    return res.status(500).json({
      error: "No se pudo aceptar la alerta",
      detail: error.message,
    });
  }
};

exports.closeDashboardAlert = async (req, res) => {
  try {
    const alertId = `${req.params.alertId ?? ""}`.trim();
    const agentName = `${req.body.agentName ?? req.body.nombre ?? ""}`.trim();

    if (!alertId) {
      return res.status(400).json({ error: "Alerta invalida" });
    }

    if (!agentName) {
      return res.status(400).json({ error: "Agente invalido" });
    }

    const alertRef = db.collection("dashboard_alerts").doc(alertId);
    const result = await db.runTransaction(async (transaction) => {
      const doc = await transaction.get(alertRef);
      if (!doc.exists) {
        return { status: 404, error: "La alerta no existe" };
      }

      const data = doc.data();
      const status = normalizeText(data.status ?? data.estado ?? "active");
      const assigned = normalizeText(data.agenteAsignado ?? data.acceptedBy);
      const normalizedAgentName = normalizeText(agentName);

      if (status === "closed" || status === "cerrada" || status === "cerrado") {
        return { status: 200 };
      }

      if (!assigned || assigned === "sin asignar") {
        return { status: 409, error: "Primero acepta la alerta" };
      }

      if (assigned !== normalizedAgentName) {
        return { status: 403, error: "Solo el agente asignado puede cerrar la alerta" };
      }

      const update = {
        status: "closed",
        estado: "closed",
        closedBy: agentName,
        closedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      transaction.set(alertRef, update, { merge: true });
      return { status: 200, update };
    });

    if (result.status !== 200) {
      return res.status(result.status).json({ error: result.error });
    }

    const update =
      result.update ?? {
        status: "closed",
        estado: "closed",
        closedBy: agentName,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

    await db.collection("sos_alerts").doc(alertId).set(update, {
      merge: true,
    });

    await db.collection("alertas_activas").doc(alertId).set(update, {
      merge: true,
    });

    return res.status(200).json({
      message: "Alerta cerrada correctamente",
      id: alertId,
    });
  } catch (error) {
    return res.status(500).json({
      error: "No se pudo cerrar la alerta",
      detail: error.message,
    });
  }
};
