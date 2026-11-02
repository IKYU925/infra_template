## 변경 내용
<!-- 무엇을, 왜 바꿨는지 -->

## 영향 범위
- [ ] local
- [ ] dev
- [ ] prod

## 확인
- [ ] `terraform fmt` / `validate` 통과
- [ ] PR 의 terraform plan 결과를 확인했다 (예상하지 못한 destroy 없음)
- [ ] Trivy / Checkov 에서 새 HIGH 이상 이슈 없음 (예외는 사유와 함께 `.checkov.yaml` 또는 인라인 skip)
- [ ] Ansible 변경 시 `ansible-lint` 통과

## 리뷰 요청 팀
- [ ] infra
- [ ] security
- [ ] full-stack
