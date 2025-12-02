resource "aws_dynamodb_table" "critalert_status" {
  name           = "CritAlert_Status"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "result_id"
  attribute {
    name = "result_id"
    type = "S"
  }
}

resource "aws_sns_topic" "alerts" {
  name = "\${var.project_name}-physician-alerts"
}

resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.email_subscription
}

resource "aws_sns_topic_subscription" "sms_sub_1" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "sms"
  endpoint  = var.sms_subscription_1
}

resource "aws_sns_topic_subscription" "sms_sub_2" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "sms"
  endpoint  = var.sms_subscription_2
}

resource "aws_iam_role" "lambda_role" {
  name = "\${var.project_name}_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "\${var.project_name}_lambda_policy"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Action = ["logs:*"], Effect = "Allow", Resource = "*" },
      { Action = ["dynamodb:PutItem"], Effect = "Allow", Resource = aws_dynamodb_table.critalert_status.arn },
      { Action = ["states:StartExecution"], Effect = "Allow", Resource = "*" }
    ]
  })
}

resource "aws_iam_role" "sfn_role" {
  name = "\${var.project_name}_sfn_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "states.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "sfn_policy" {
  name = "\${var.project_name}_sfn_policy"
  role = aws_iam_role.sfn_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Action = ["sns:Publish"], Effect = "Allow", Resource = aws_sns_topic.alerts.arn },
      { Action = ["dynamodb:GetItem"], Effect = "Allow", Resource = aws_dynamodb_table.critalert_status.arn }
    ]
  })
}

resource "aws_sfn_state_machine" "critalert_workflow" {
  name     = "\${var.project_name}_Workflow"
  role_arn = aws_iam_role.sfn_role.arn
  definition = <<DEFINITION
{
  "StartAt": "NotificarMedico",
  "States": {
    "NotificarMedico": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "\${aws_sns_topic.alerts.arn}",
        "Message.$": "States.Format('ALERTA CRITICA ({}.): {} ({}) tiene {} en {} (Rango: {}). Dr. a cargo: {}. Motivo: {}', $.criticality.level, $.patient_name, $.patient_id, $.test_name, $.value, $.reference_range, $.ordering_physician.name, $.criticality.reason)",
        "Subject": "ALERTA CRITICA - \$.test_name"
      },
      "ResultPath": "$.sns_result",
      "Next": "EsperarAck"
    },
    "EsperarAck": {
      "Type": "Wait",
      "Seconds": 60,
      "Next": "VerificarEstado"
    },
    "VerificarEstado": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:getItem",
      "Parameters": {
        "TableName": "\${aws_dynamodb_table.critalert_status.name}",
        "Key": { "result_id": { "S.$": "$.result_id" } }
      },
      "ResultPath": "$.status_check",
      "Next": "FueConfirmado?"
    },
    "FueConfirmado?": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.status_check.Item.acknowledged.BOOL",
          "BooleanEquals": true,
          "Next": "AlertaResuelta"
        }
      ],
      "Default": "EscalarBackup"
    },
    "EscalarBackup": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "\${aws_sns_topic.alerts.arn}",
        "Message.$": "States.Format('ESCALAMIENTO URGENTE: El Dr. {} no respondió. Paciente {} (ID: {}) tiene {} en {}. Contactar a Dr. Backup: {}', $.ordering_physician.name, $.patient_name, $.patient_id, $.test_name, $.value, $.backup_physician.name)",
        "Subject": "ESCALAMIENTO URGENTE"
      },
      "End": true
    },
    "AlertaResuelta": { "Type": "Succeed" }
  }
}
DEFINITION
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "lambda_function.zip"
  source_file = "../lambda/lambda_function.py"
}

resource "aws_lambda_function" "router" {
  filename         = "lambda_function.zip"
  function_name    = "\${var.project_name}_Router"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.12"
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.critalert_status.name
      SFN_ARN    = aws_sfn_state_machine.critalert_workflow.arn
    }
  }
}

resource "aws_apigatewayv2_api" "http_api" {
  name          = "\${var.project_name}_API"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type"]
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "\$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.router.invoke_arn
}

resource "aws_apigatewayv2_route" "post_result" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /result"
  target    = "integrations/\${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.router.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "\${aws_apigatewayv2_api.http_api.execution_arn}/*/*/result"
}

resource "aws_s3_bucket" "web_bucket" {
  bucket = "\${var.project_name}-web-\${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.web_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.web_bucket.id
  index_document { suffix = "index.html" }
}

resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.web_bucket.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "PublicReadGetObject",
      Effect    = "Allow",
      Principal = "*",
      Action    = "s3:GetObject",
      Resource  = "\${aws_s3_bucket.web_bucket.arn}/*"
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.public_access]
}

resource "aws_s3_object" "html" {
  bucket       = aws_s3_bucket.web_bucket.id
  key          = "index.html"
  source       = "../web/index.html"
  content_type = "text/html"
}

resource "aws_s3_object" "config" {
  bucket       = aws_s3_bucket.web_bucket.id
  key          = "config.json"
  content      = jsonencode({ api_url = "\${aws_apigatewayv2_api.http_api.api_endpoint}/result" })
  content_type = "application/json"
  source       = "../web/config.json"
}