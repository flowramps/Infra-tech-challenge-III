# Remote state in a local S3-compatible bucket (see bootstrap/).
# Connection settings are supplied at init time with -backend-config,
# one file per environment under environments/<env>/backend.hcl.
terraform {
  backend "s3" {}
}
