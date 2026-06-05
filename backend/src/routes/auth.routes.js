const express = require("express");
const router = express.Router();

const authController = require("../controllers/auth.controller");
const paymentController = require("../controllers/payment.controller");

router.post("/register", authController.register);
router.post("/agent-login", authController.loginAgent);
router.post("/profile", authController.saveProfile);
router.post("/dashboard-alert", authController.saveDashboardAlert);
router.get("/dashboard-alerts", authController.listDashboardAlerts);
router.post("/dashboard-alerts/:alertId/accept", authController.acceptDashboardAlert);
router.post("/dashboard-alerts/:alertId/close", authController.closeDashboardAlert);
router.get("/companies", paymentController.listCompanies);
router.get("/payments/company-status", paymentController.companyStatus);
router.post("/payments/company-preference", paymentController.createCompanyPreference);
router.post("/payments/mercadopago/webhook", paymentController.mercadoPagoWebhook);
router.get("/payments/mercadopago/return", paymentController.mercadoPagoReturn);


module.exports = router;
