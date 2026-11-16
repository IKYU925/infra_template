# 코어타임에만 띄운다. 올리고 내리는 것은 eks.sh (make eks-up / eks-down) 와 .github/workflows/eks.yml
region              = "ap-northeast-2"
allowed_account_ids = ["111111111111"]               # TODO: 실습 계정 ID
state_bucket        = "CHANGE_ME-tfstate-ACCOUNT_ID" # TODO: backend.hcl 의 bucket

endpoint_allowed_cidrs = [] # 운영자 고정 IP 가 있으면 넣는다. 실행하는 곳의 IP 는 eks.sh 가 caller_cidr 로 더한다
admin_principal_arns = [
  # "arn:aws:iam::111111111111:role/<운영자 역할 또는 사용자>",
  # "arn:aws:iam::111111111111:role/myproject-dev-gha-apply",
]
