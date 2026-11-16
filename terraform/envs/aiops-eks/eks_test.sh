#!/usr/bin/env bash
# eks.sh keep-up 의 코어타임 판단. 실행: terraform/envs/aiops-eks/eks_test.sh
set -u
S="$(dirname "$0")/eks.sh"
fail=0
check() {
  local want="$1"; shift
  if "$S" keep-up "$@"; then got=keep; else got=down; fi
  [[ "$got" == "$want" ]] || { echo "FAIL keep-up $* -> $got (want $want)"; fail=1; }
}
D=2026-11-17
check down 2 09:29 $D
check keep 2 09:30 $D
check keep 2 11:59 $D
check down 2 12:00 $D
check down 6 10:00 $D
check down 7 10:00 $D
check keep 2 12:30 $D "${D}T12:40"
check down 2 12:40 $D "${D}T12:40"
check keep 2 12:59 $D "${D}T15:00"
check down 2 13:00 $D "${D}T15:00"
check down 2 12:30 $D "2026-11-16T13:00"
check down 2 12:30 $D "13:00"
check keep 2 11:00 $D "${D}T11:00"
[[ $fail == 0 ]] && echo "ok keep-up" || exit 1
