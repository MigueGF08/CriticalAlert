data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "lambda_function.zip"
  source_file = "../lambda/lambda_function.py"
}

resource "aws_lambda_function" "router" {
  filename         = "lambda_function.zip"
  function_name    = "${var.project_name}_Router"
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
