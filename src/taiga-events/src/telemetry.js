/*
 * Telemetría propia del equipo (no es código de Taiga). Se carga antes que la
 * app con `node --require ./src/telemetry.js` (ver Dockerfile), para que winston
 * quede instrumentado desde el primer require.
 *
 * Con APPLICATIONINSIGHTS_CONNECTION_STRING envía a Application Insights:
 *   - logs de winston            -> tabla traces (con cloud_RoleName = OTEL_SERVICE_NAME)
 *   - excepciones no controladas -> tabla exceptions (tipo, mensaje y stack)
 * Sin ella (docker-compose) no hace nada.
 */
if (process.env.APPLICATIONINSIGHTS_CONNECTION_STRING) {
  const { useAzureMonitor, shutdownAzureMonitor } = require("@azure/monitor-opentelemetry");
  const { logs, SeverityNumber } = require("@opentelemetry/api-logs");

  useAzureMonitor({
    // Las peticiones HTTP son solo los probes de /healthz: no se trazan.
    instrumentationOptions: {
      http: { enabled: false },
      winston: { enabled: true }
    }
  });

  const otelLogger = logs.getLogger("taiga-events");

  // Taiga registra su propio handler, que hace process.exit(1) de inmediato.
  // Este corre antes (se registró primero) y deja la excepción con su stack.
  const reportCrash = kind => err => {
    const error = err instanceof Error ? err : new Error(String(err));
    otelLogger.emit({
      severityNumber: SeverityNumber.FATAL,
      severityText: "FATAL",
      body: `${kind}: ${error.message}`,
      attributes: {
        "exception.type": error.name,
        "exception.message": error.message,
        "exception.stacktrace": error.stack || "",
        "taiga.phase": "runtime"
      }
    });
  };
  process.on("uncaughtException", reportCrash("uncaughtException"));
  process.on("unhandledRejection", reportCrash("unhandledRejection"));

  // process.exit() termina sin esperar a los exportadores (que envían por lotes):
  // se envía lo pendiente primero, con un tope de 5 s.
  const exit = process.exit.bind(process);
  let exiting = false;
  process.exit = code => {
    if (exiting) return;
    exiting = true;
    const timeout = new Promise(resolve => setTimeout(resolve, 5000).unref());
    Promise.race([shutdownAzureMonitor(), timeout])
      .catch(() => {})
      .finally(() => exit(code));
  };
}
