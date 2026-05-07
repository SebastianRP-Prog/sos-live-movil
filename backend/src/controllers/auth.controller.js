const { admin, db } = require("../config/firebase");

const GMAIL_REGEX = /^[^\s@]+@gmail\.com$/i;
const PHONE_REGEX = /^\d{10,15}$/;
const PASSWORD_REGEX = /^(?=.*[A-Za-z])(?=.*\d).{8,}$/;

const normalizeEmail = (value = "") => value.trim().toLowerCase();
const normalizePhone = (value = "") => value.replace(/\D/g, "");

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
