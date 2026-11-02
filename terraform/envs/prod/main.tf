module "platform" {
  source = "../../modules/platform"

  project     = var.project
  environment = var.environment

  vpc_cidr                = var.vpc_cidr
  az_count                = var.az_count
  single_nat_gateway      = var.single_nat_gateway
  enable_flow_log         = var.enable_flow_log
  flow_log_retention_days = var.flow_log_retention_days
  app_ingress_cidrs       = var.app_ingress_cidrs

  app_instance_count   = var.app_instance_count
  app_instance_type    = var.app_instance_type
  app_root_volume_size = var.app_root_volume_size

  db_engine_version        = var.db_engine_version
  db_instance_class        = var.db_instance_class
  db_allocated_storage     = var.db_allocated_storage
  db_max_allocated_storage = var.db_max_allocated_storage
  db_multi_az              = var.db_multi_az
  db_backup_retention_days = var.db_backup_retention_days
  db_deletion_protection   = var.db_deletion_protection

  artifact_bucket_force_destroy = var.artifact_bucket_force_destroy
}
