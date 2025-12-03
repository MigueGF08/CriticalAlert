resource "aws_dynamodb_table" "critalert_status" {
  name           = "CritAlert_Status"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "result_id"
  attribute {
    name = "result_id"
    type = "S"
  }
}
