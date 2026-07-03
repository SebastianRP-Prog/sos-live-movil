require("dotenv").config();

const { admin, db } = require("../src/config/firebase");

const [companyId, name, rawPrice, rawPlanDays = "30"] = process.argv.slice(2);
const price = Number(rawPrice);
const planDays = Number(rawPlanDays);

if (
  !companyId ||
  !name ||
  !Number.isFinite(price) ||
  price <= 0 ||
  !Number.isInteger(planDays) ||
  planDays <= 0
) {
  console.error(
    'Uso: npm run seed:company -- empresa-id "Nombre empresa" 50000 30',
  );
  process.exit(1);
}

db.collection("companies")
  .doc(companyId)
  .set(
    {
      name,
      description: `Plan de acceso con ${name}`,
      price,
      currency: "COP",
      planDays,
      active: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  )
  .then(() => {
    console.log(`Empresa ${companyId} configurada por COP ${price}.`);
  })
  .catch((error) => {
    console.error("No se pudo configurar la empresa:", error);
    process.exitCode = 1;
  })
  .finally(() => admin.app().delete());
