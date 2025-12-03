# CritAlert — Arquitectura

Este documento describe la arquitectura de alto nivel, componentes, flujo de datos, modelo de estados y recomendaciones para `ProyectoCritico`.

Resumen
- Propósito: detectar resultados de laboratorio críticos y notificar al personal médico, persistiendo el estado y escalando si no hay acuse.
- Componentes principales: API Gateway (HTTP), Lambda (evaluación y encolado), DynamoDB (estado), Step Functions (orquestación), SNS (notificaciones), S3 (frontend estático).

Diagrama de alto nivel (ASCII)

Client (web / curl)
  |
  | POST /result
  v
API Gateway (HTTP API) ---> Lambda Router (`lambda/lambda_function.py`)
  |
  | Si crítico: PutItem en DynamoDB
  |             StartExecution en Step Functions
  v
DynamoDB (CritAlert_Status)  <--- Step Functions consulta estado (GetItem)
  |
SNS Topic (physician-alerts) <-- Step Functions publica notificación
  |
  +--> Email/SMS a médicos (suscripciones)


Componentes y responsabilidades
- API Gateway v2 (HTTP API): expone la ruta `POST /result` y enruta a la Lambda.
- Lambda (`lambda/lambda_function.py`): recibe el payload, valida/extrae campos, decide si el resultado es crítico (regla simple para Potassium), escribe un item con estado `PENDING` en la tabla DynamoDB y arranca la Step Function.
- DynamoDB (`CritAlert_Status`): tabla con `result_id` como hash key; contiene `status`, `acknowledged` (BOOL), `timestamp` y `details_summary`.
- Step Functions: orquesta la notificación (publica a SNS), espera un tiempo (60s en la definición actual), consulta la tabla y decide si escalar a un backup o terminar si ya fue confirmado.
- SNS: tema para notificaciones; tiene suscripciones de email y SMS configuradas por Terraform.
- S3 + Sitio estático (`web/`): pequeña interfaz para generar y enviar eventos de prueba al API.
- Terraform (`terraform/`): define todos los recursos, empaqueta la Lambda (zip), sube contenido web a S3 y crea la Step Function con la definición embebida.

Flujo de datos (paso a paso)
1. El cliente envía un JSON con datos del resultado a `POST /result`.
2. API Gateway invoca la Lambda.
3. La Lambda determina si el resultado es crítico:
   - Si NO crítico: responde con estado `NORMAL`.
   - Si crítico: escribe un item en DynamoDB con `result_id`, `status: PENDING`, `acknowledged: false` y lanza la Step Function proporcionando el payload original.
4. La Step Function publica un mensaje a SNS (notificación primaria) y espera (60s).
5. Tras la espera, la Step Function hace `GetItem` en DynamoDB para comprobar `acknowledged`:
   - Si `acknowledged == true`: termina exitosamente.
   - Si no: publica un mensaje de escalamiento a SNS (backup) y termina.

Modelo de datos (DynamoDB)
- Tabla: `CritAlert_Status`
- Hash key: `result_id` (S)
- Atributos almacenados por la Lambda (ejemplo):
  - `result_id`: string
  - `status`: string (e.g., `PENDING`, `CRITICAL_ALERT_SENT`)
  - `acknowledged`: BOOL
  - `timestamp`: ISO-8601 string
  - `details_summary`: string

Ejemplo de evento que envía el frontend
```json
{
  "result_id": "RES-CRIT-001",
  "patient_id": "P123456",
  "patient_name": "John Smith",
  "test_name": "Potassium",
  "value": 6.8,
  "is_critical": true,
  "criticality": { "level": "SEVERE", "reason": "High K", "action_required": "Immediate" },
  "ordering_physician": { "name": "Dr. Sarah Johnson", "phone": "+1-555-0101" }
}
```

Consideraciones de diseño y operativas
- Idempotencia: la Lambda genera `result_id` si no se proporciona; sin embargo, para evitar duplicados y ejecuciones repetidas de Step Functions, se recomienda que el productor (LIS o sistema de laboratorio) provea `result_id` único.
- Retries y errores: la Step Function actual espera 60s y consulta DynamoDB; en escenarios reales conviene aumentar el tiempo, usar backoffs y reintentos, y manejar errores (GetItem fallido) mediante catchers en la definición.
- Seguridad:
  - Restringir políticas IAM: en vez de `Resource = "*"` para `states:StartExecution`, usar el ARN concreto del state machine.
  - Habilitar cifrado en reposo para la tabla DynamoDB y el bucket S3 si maneja datos sensibles.
  - Asegurar que el bucket S3 tenga políticas públicas solo si es necesario (actualmente la configuración lo hace público para el frontend estático).
  - Habilitar WAF o controles de rate limiting en el API en producción.
- Observabilidad:
  - Añadir logs estructurados en la Lambda (CloudWatch), métricas personalizadas y alarmas (p. ej. número de alertas críticas por minuto).
  - Usar X-Ray para trazabilidad entre Lambda y Step Functions.
- Costos:
  - SNS + SMS puede generar costes significativos si se envían SMS internacionales; considerar llamadas telefónicas/rotas alternativas o limitar SMS para escalamiento solo.

Extensiones y mejoras recomendadas
- Añadir verificación de autenticidad: firmar requests o usar API keys/JWT para evitar uso no autorizado del endpoint.
- Añadir un endpoint para que el médico confirme la recepción (set `acknowledged = true`) — actualmente la idea es que la confirmación actualice el item DynamoDB.
- Añadir outputs de Terraform que expongan la URL del API, el ARN del state machine y el nombre de la tabla. Ejemplo de `outputs.tf` sugerido:

```hcl
output "api_endpoint" {
  value = aws_apigatewayv2_api.http_api.api_endpoint
}

output "sfn_arn" {
  value = aws_sfn_state_machine.critalert_workflow.arn
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.critalert_status.name
}
```

- Hacer la función Lambda más configurable (lista de tests y umbrales en un archivo de configuración o en variables de entorno) en vez de lógica hardcodeada.

Pruebas y despliegue
- Local: servir `web/` y actualizar `web/config.json` con la URL del API para pruebas manuales.
- Terraform: revise `terraform/variables.tf` antes de aplicar; las variables incluyen `email_subscription` y `sms_subscription_*`.
- Añadir pipeline CI/CD: empaquetado de la Lambda, `terraform init/plan/apply` con controles de seguridad (aplicar en entorno de staging primero).

Resumen de acciones recomendadas para producción
1. Restringir IAM a ARNs concretos.
2. Habilitar cifrado y controles de acceso para datos sensibles.
3. Añadir pruebas automatizadas y despliegue controlado (staging/production).
4. Añadir outputs de Terraform y/o script de despliegue para facilitar pruebas.

Si quieres, puedo:
- añadir los `outputs.tf` sugeridos dentro de `terraform/` ahora,
- crear un pequeño `deploy.ps1` que haga empaquetado de la lambda y ejecute `terraform init/plan/apply`,
- o generar un diagrama visual (SVG/PNG) y añadirlo al repositorio.
