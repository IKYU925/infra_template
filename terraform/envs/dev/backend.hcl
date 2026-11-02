# terraform/bootstrap 을 먼저 apply 한 뒤 출력값으로 채운다.
bucket         = "CHANGE_ME-tfstate-ACCOUNT_ID"
key            = "envs/dev/terraform.tfstate"
region         = "ap-northeast-2"
dynamodb_table = "CHANGE_ME-tflock"
encrypt        = true

# 참고: Terraform 1.10+ 는 S3 자체 잠금(use_lockfile)을 지원하고 dynamodb_table 은 deprecated 경고가 난다.
# 지금은 팀 합의대로 DynamoDB 잠금을 쓰고, 전환할 때는 아래 줄을 켜서 두 잠금을 함께 쓰다가 dynamodb_table 을 지운다.
# use_lockfile = true
