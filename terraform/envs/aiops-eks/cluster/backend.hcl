# terraform/bootstrap 을 먼저 apply 한 뒤 출력값으로 채운다. base/backend.hcl, terraform.tfvars 의 state_bucket 과 같은 버킷이다.
bucket         = "CHANGE_ME-tfstate-ACCOUNT_ID"
key            = "envs/aiops-eks/cluster/terraform.tfstate"
region         = "ap-northeast-2"
dynamodb_table = "CHANGE_ME-tflock"
encrypt        = true
