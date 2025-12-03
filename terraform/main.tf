# Este archivo main.tf ahora está organizado en módulos separados
# Cada componente está en su propio archivo .tf para mejor mantenibilidad

# Archivos incluidos:
# - dynamodb.tf: Configuración de DynamoDB
# - sns.tf: Configuración de SNS y suscripciones
# - iam.tf: Roles y políticas de IAM
# - step_functions.tf: Definición de la Step Function
# - lambda.tf: Función Lambda y su configuración
# - api_gateway.tf: Configuración del API Gateway
# - s3.tf: Configuración del bucket S3 y contenido
# - variables.tf: Variables de entrada
# - outputs.tf: Salidas de Terraform
# - providers.tf: Configuración de proveedores