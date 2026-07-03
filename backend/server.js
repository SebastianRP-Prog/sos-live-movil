require("dotenv").config();

const app = require("./src/app");

const PORT = Number(process.env.PORT || 3000);

process.on("uncaughtException", (error) => {
  console.error("Uncaught exception:", error);
});

process.on("unhandledRejection", (error) => {
  console.error("Unhandled rejection:", error);
});

process.on("exit", (code) => {
  console.log(`Servidor finalizado con codigo ${code}`);
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Servidor corriendo en http://localhost:${PORT}`);
});
