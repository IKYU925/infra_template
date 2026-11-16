# 코어타임에만 띄운다. 올리고 내리는 것은 eks.sh (make eks-up / eks-down) 와 .github/workflows/eks.yml
region              = "ap-northeast-2"
allowed_account_ids = ["646170419715"]
state_bucket        = "myproject-dev-tfstate-646170419715"

endpoint_allowed_cidrs = [] # 운영자 고정 IP 가 있으면 넣는다. 실행하는 곳의 IP 는 eks.sh 가 caller_cidr 로 더한다
admin_principal_arns = [
  "arn:aws:iam::646170419715:user/ikgyu_admin",
  "arn:aws:iam::646170419715:role/myproject-dev-gha-apply-5a77fa6c9e15aa49035aeb80fd",
]
