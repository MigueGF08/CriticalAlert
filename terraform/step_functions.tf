resource "aws_sfn_state_machine" "critalert_workflow" {
  name     = "${var.project_name}_Workflow"
  role_arn = aws_iam_role.sfn_role.arn
  definition = <<DEFINITION
{
  "StartAt": "NotificarMedico",
  "States": {
    "NotificarMedico": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "${aws_sns_topic.alerts.arn}",
        "Message.$": "States.Format('ALERTA CRITICA ({}.): {} ({}) tiene {} en {} (Rango: {}). Dr. a cargo: {}. Motivo: {}', $.criticality.level, $.patient_name, $.patient_id, $.test_name, $.value, $.reference_range, $.ordering_physician.name, $.criticality.reason)",
        "Subject": "ALERTA CRITICA - $.test_name"
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
        "TableName": "${aws_dynamodb_table.critalert_status.name}",
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
        "TopicArn": "${aws_sns_topic.alerts.arn}",
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
