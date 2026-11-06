module "platform" {
  source = "../../modules/platform"

  project     = var.project
  environment = var.environment

  vpc_cidr                = var.vpc_cidr
  az_count                = var.az_count
  single_nat_gateway      = var.single_nat_gateway
  enable_flow_log         = var.enable_flow_log
  flow_log_retention_days = var.flow_log_retention_days

  eks_version              = var.eks_version
  eks_public_access_cidrs  = var.eks_public_access_cidrs
  eks_admin_principal_arns = var.eks_admin_principal_arns
  node_instance_types      = var.node_instance_types
  node_min_size            = var.node_min_size
  node_max_size            = var.node_max_size
  node_desired_size        = var.node_desired_size

  ecr_push_principal_arns = var.ecr_push_principal_arns
  ecr_force_delete        = var.ecr_force_delete

  db_engine_version        = var.db_engine_version
  db_instance_class        = var.db_instance_class
  db_allocated_storage     = var.db_allocated_storage
  db_max_allocated_storage = var.db_max_allocated_storage
  db_multi_az              = var.db_multi_az
  db_backup_retention_days = var.db_backup_retention_days
  db_deletion_protection   = var.db_deletion_protection

  artifact_bucket_force_destroy = var.artifact_bucket_force_destroy
}
