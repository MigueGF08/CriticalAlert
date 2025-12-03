output "api_endpoint" {
  description = "Public endpoint for the HTTP API"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}

output "sfn_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.critalert_workflow.arn
}

output "dynamodb_table_name" {
  description = "DynamoDB table name for alert status"
  value       = aws_dynamodb_table.critalert_status.name
}

output "web_bucket" {
  description = "S3 bucket used for static web hosting"
  value       = aws_s3_bucket.web_bucket.bucket
}
