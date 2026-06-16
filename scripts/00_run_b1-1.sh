#!/bin/bash

source library.sh

cd assignment_scripts || exit 1

bash 00_init_vm.sh

echo 
echo "=============================="
read -p "B1-1 과제를 시작하려면 Enter를 누르세요.."
echo "=============================="

run_step 01_security.sh "01. SSH 설정 및 방화벽 설정을 완료했습니다."
run_step 02_user_setup.sh "02. 계정/그룹 생성 및 디렉토리 구조 생성을 완료했습니다."
run_step 03_user_modify.sh "03. 디렉토리 권한 설정(ACL 포함)을 완료했습니다."
run_step 04_app_setup.sh "04. 앱 실행 준비를 완료했습니다."
run_step 05_operations.sh "05. 운영 관리 및 모니터링을 완료했습니다."

echo 
echo "모든 단계를 완료했습니다."
read -p "종료하려면 Enter를 누르세요.."
echo "=============================="