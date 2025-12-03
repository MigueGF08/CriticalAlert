resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}_lambda_policy"
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
  name = "${var.project_name}_sfn_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "states.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "sfn_policy" {
  name = "${var.project_name}_sfn_policy"
  role = aws_iam_role.sfn_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Action = ["sns:Publish"], Effect = "Allow", Resource = aws_sns_topic.alerts.arn },
      { Action = ["dynamodb:GetItem"], Effect = "Allow", Resource = aws_dynamodb_table.critalert_status.arn }
    ]
  })
}
