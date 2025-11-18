resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.sse_algorithm
    }
  }
}
********************************************************************************
variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket"
}

variable "versioning" {
  type        = bool
  default     = true
}

variable "sse_algorithm" {
  type        = string
  default     = "AES256"
}

variable "tags" {
  type        = map(string)
  default     = {}
}
****************************************************************************
output "bucket_name" {
  value = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}
**************************************************************

provider "aws" {
  region = "ap-south-1" # change if needed
}
**************************************************************
module "test_bucket" {
  source = "../../"
  bucket_name = "sample-demo-bucket-${random_id.suffix.hex}"
  versioning  = true
  tags = {
    Environment = "dev"
    Owner       = "testing"
  }
}
resource "random_id" "suffix" {
  byte_length = 2
}
*********************************************************
output "test_bucket_name" {
  value = module.test_bucket.bucket_name
}

output "test_bucket_arn" {
  value = module.test_bucket.bucket_arn
}
*****************************************************************************************************************************************************
************************************************************************************
resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  acl    = var.acl
  force_destroy = var.force_destroy
  tags = merge(var.default_tags, var.tags)
  # Optional website hosting
  dynamic "website" {
    for_each = var.website_enabled ? [1] : []
    content {
      index_document = var.website_index_document
      error_document = var.website_error_document
    }
  }
  versioning {
    enabled = var.versioning
    mfa_delete = var.mfa_delete
  }
  server_side_encryption_configuration {
    dynamic "rule" {
      for_each = var.enable_default_encryption ? [1] : []
      content {
        apply_server_side_encryption_by_default {
          sse_algorithm = var.sse_algorithm
          kms_master_key_id = var.sse_algorithm == "aws:kms" && var.use_existing_kms_key ? var.kms_key_arn : (var.sse_algorithm == "aws:kms" && !var.use_existing_kms_key ? aws_kms_key.s3_key.arn : null)
        }
      }
    }
  }
  lifecycle_rule {
    # default rule to keep current versions for 365 days; additional rules in lifecycle.tf
    id      = "default-expire"
    enabled = true
    noncurrent_version_expiration {
      days = var.noncurrent_version_expiration_days
    }
  }
  object_lock_configuration {
    dynamic "rule" {
      for_each = var.object_lock_enabled ? [1] : []
      content {
        object_lock_enabled = "Enabled"
        rule {
          default_retention {
            mode = var.object_lock_mode
            days = var.object_lock_days != 0 ? var.object_lock_days : null
            years = var.object_lock_years != 0 ? var.object_lock_years : null
          }
        }
      }
    }
  }
}
# Block public access
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id
  block_public_acls       = var.block_public_acls
  block_public_policy     = var.block_public_policy
  ignore_public_acls      = var.ignore_public_acls
  restrict_public_buckets = var.restrict_public_buckets
}
# Access logging target bucket (optional)
resource "aws_s3_bucket" "access_log_target" {
  count  = var.enable_access_logging && var.access_logs_bucket_name == "" ? 1 : 0
  bucket = var.access_logs_bucket_name == "" ? "${var.bucket_name}-access-logs-${random_id.access_logs_suffix.hex}" : var.access_logs_bucket_name
  acl    = "log-delivery-write"
  tags = merge(var.default_tags, { "Name" = "access-logs-${var.bucket_name}" })
}
resource "random_id" "access_logs_suffix" {
  count       = var.enable_access_logging && var.access_logs_bucket_name == "" ? 1 : 0
  byte_length = 2
}
resource "aws_s3_bucket_logging" "this" {
  bucket = aws_s3_bucket.this.id
  dynamic "target_bucket" {
    for_each = var.enable_access_logging ? [1] : []
    content {
      target_bucket = var.access_logs_bucket_name != "" ? var.access_logs_bucket_name : aws_s3_bucket.access_log_target[0].id
      target_prefix = var.access_logs_prefix
    }
  }
  depends_on = [
    aws_s3_bucket_public_access_block.this
  ]
}
********************************************
# Optional replication configuration
resource "aws_s3_bucket_replication_configuration" "this" {
  count  = var.enable_replication ? 1 : 0
  bucket = aws_s3_bucket.this.id
  role   = var.replication_role_arn
  dynamic "rule" {
    for_each = var.enable_replication ? var.replication_rules : []
    content {
      id     = rule.value.id
      status = rule.value.status
      filter {
        prefix = lookup(rule.value, "prefix", "")
      }
      dynamic "destination" {
        for_each = [1]
        content {
          bucket        = rule.value.destination_bucket_arn
          storage_class = lookup(rule.value, "storage_class", null)
          account_id    = lookup(rule.value, "destination_account_id", null)
        }
      }
      dynamic "existing_object_replication" {
        for_each = lookup(rule.value, "replicate_existing_objects", false) ? [1] : []
        content {
          status = "Enabled"
        }
      }
    }
  }
}
******************************************************************************
# Optional bucket policy to enforce TLS and encryption
resource "aws_s3_bucket_policy" "enforce" {
  count  = var.create_encryption_and_tls_policy ? 1 : 0
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.enforce.json
}
**********************************************************
data "aws_iam_policy_document" "enforce" {
  count = var.create_encryption_and_tls_policy ? 1 : 0
  # Deny unsecure transport
  statement {
    sid    = "DenyUnsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
  # Deny puts without server-side encryption
  statement {
    sid    = "DenyUnEncryptedObjectUploads"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:PutObject", "s3:PutObjectAcl"]
    resources = ["${aws_s3_bucket.this.arn}/*"]
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = [var.sse_algorithm == "aws:kms" ? "aws:kms" : "AES256"]
    }
  }
}
***************************************************************************
resource "aws_kms_key" "s3_key" {
  count = var.sse_algorithm == "aws:kms" && !var.use_existing_kms_key ? 1 : 0
  description = "KMS key for S3 bucket ${var.bucket_name}"
  deletion_window_in_days = var.kms_deletion_window_days
  key_usage = "ENCRYPT_DECRYPT"
  policy = var.kms_key_policy != "" ? var.kms_key_policy : null
  tags = merge(var.default_tags, var.tags)
}
resource "aws_kms_alias" "s3_key_alias" {
  count   = var.sse_algorithm == "aws:kms" && !var.use_existing_kms_key ? 1 : 0
  name    = "alias/${var.kms_alias}"
  target_key_id = aws_kms_key.s3_key[0].id
}
******************************************************************************
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = length(var.additional_lifecycle_rules) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id
  dynamic "rule" {
    for_each = var.additional_lifecycle_rules
    content {
      id      = rule.value.id
      enabled = lookup(rule.value, "enabled", true)
      filter {
        prefix = lookup(rule.value, "prefix", "")
      }
      transition {
        days          = lookup(rule.value, "transition_days", null)
        storage_class = lookup(rule.value, "transition_storage_class", null)
      }
      expiration {
        days = lookup(rule.value, "expiration_days", null)
      }
****************************************************************************************
      noncurrent_version_transition {
        days          = lookup(rule.value, "noncurrent_version_transition_days", null)
        storage_class = lookup(rule.value, "noncurrent_version_transition_storage_class", null)
      }
      noncurrent_version_expiration {
        days = lookup(rule.value, "noncurrent_version_expiration_days", null)
      }
      abort_incomplete_multipart_upload {
        days_after_initiation = lookup(rule.value, "abort_multipart_days", null)
      }
    }
  }
}
***************************************************************************************************
# Useful policy outputs for replication - users may supply role; we also output ARNs
# If users want to create replication role/policy here we can add, but many orgs supply central role.
*****************************************************************************************************
variable "bucket_name" {
  description = "S3 bucket name"
  type        = string
}
variable "acl" {
  description = "S3 ACL"
  type        = string
  default     = "private"
}
variable "force_destroy" {
  description = "Allow destroy even if bucket has objects"
  type        = bool
  default     = false
}
variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
variable "default_tags" {
  description = "Default tags added to all resources"
  type        = map(string)
  default     = {
    ManagedBy = "terraform"
    Terraform = "true"
  }
}
variable "region" {
  description = "AWS region (for docs/optional use)"
  type        = string
  default     = "ap-south-1"
}
# Versioning and object lock
variable "versioning" {
  description = "Enable versioning"
  type        = bool
  default     = true
}
**********************************************************************
variable "mfa_delete" {
  description = "Enable MFA delete (note: only works for AWS console & specific flows)"
  type        = bool
  default     = false
}
variable "object_lock_enabled" {
  description = "Enable object lock on the bucket"
  type        = bool
  default     = false
}
variable "object_lock_mode" {
  description = "Object lock default retention mode (GOVERNANCE or COMPLIANCE)"
  type        = string
  default     = "GOVERNANCE"
}
variable "object_lock_days" {
  description = "Retention in days (0 if using years)"
  type        = number
  default     = 0
}
variable "object_lock_years" {
  description = "Retention in years (0 if using days)"
  type        = number
  default     = 0
}
***************************************************************************
# Encryption
variable "enable_default_encryption" {
  description = "Enable default bucket encryption"
  type        = bool
  default     = true
}
variable "sse_algorithm" {
  description = "SSE algorithm (AES256 or aws:kms)"
  type        = string
  default     = "AES256"
}
variable "use_existing_kms_key" {
  description = "If true, you supply kms_key_arn"
  type        = bool
  default     = false
}
variable "kms_key_arn" {
  description = "Existing KMS key ARN (used if use_existing_kms_key == true)"
  type        = string
  default     = ""
}
variable "kms_alias" {
  description = "Alias for created KMS key"
  type        = string
  default     = "s3-module-key"
}
variable "kms_deletion_window_days" {
  description = "KMS deletion window"
  type        = number
  default     = 30
}
variable "kms_key_policy" {
  description = "Optional JSON policy override for the KMS key"
  type        = string
  default     = ""
}
**********************************************************************************
# Lifecycle
variable "noncurrent_version_expiration_days" {
  description = "Default days to expire noncurrent versions"
  type        = number
  default     = 365
}
variable "additional_lifecycle_rules" {
  description = "List of additional lifecycle rules as objects"
  type = list(object({
    id                                    = string
    enabled                               = optional(bool, true)
    prefix                                = optional(string, "")
    transition_days                       = optional(number, null)
    transition_storage_class              = optional(string, null)
    expiration_days                       = optional(number, null)
    noncurrent_version_transition_days    = optional(number, null)
    noncurrent_version_transition_storage_class = optional(string, null)
    noncurrent_version_expiration_days    = optional(number, null)
    abort_multipart_days                  = optional(number, null)
  }))
  default = []
}
**************************************************************************************
# Access logging
variable "enable_access_logging" {
  type    = bool
  default = false
}
variable "access_logs_bucket_name" {
  description = "If empty and enable_access_logging true, module will create a bucket for logs"
  type        = string
  default     = ""
}
variable "access_logs_prefix" {
  type    = string
  default = "access-logs/"
}
# Replication (left flexible; requires external role & destination bucket)
variable "enable_replication" {
  type    = bool
  default = false
}
variable "replication_role_arn" {
  type    = string
  default = ""
}
***********************************************************
variable "replication_rules" {
  description = "List of replication rules"
  type = list(object({
    id                       = string
    status                   = string
    prefix                   = optional(string, "")
    destination_bucket_arn   = string
    destination_account_id   = optional(string, null)
    storage_class            = optional(string, null)
    replicate_existing_objects = optional(bool, false)
  }))
  default = []
}
# Policies
variable "create_encryption_and_tls_policy" {
  description = "Create a policy that denies unencrypted uploads and non-TLS"
  type    = bool
  default = true
}
# Website
variable "website_enabled" {
  type    = bool
  default = false
}
variable "website_index_document" {
  type    = string
  default = "index.html"
}
*******************************************************************
variable "website_error_document" {
  type    = string
  default = "error.html"
}
# Misc
variable "access_from_vpc_endpoint" {
  description = "If set, will be used by the user to add additional policy conditions (not auto applied)"
  type        = string
  default     = ""
}
****************************************************************
output "bucket_id" {
  value = aws_s3_bucket.this.id
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  value = aws_s3_bucket.this.bucket_domain_name
}

output "kms_key_arn" {
  value = var.sse_algorithm == "aws:kms" && !var.use_existing_kms_key ? aws_kms_key.s3_key[0].arn : var.kms_key_arn
  description = "KMS key ARN (created or provided) if using KMS"
}

output "access_logs_bucket" {
  value = var.enable_access_logging ? (var.access_logs_bucket_name != "" ? var.access_logs_bucket_name : aws_s3_bucket.access_log_target[0].id) : null
}
*********************************************************************
