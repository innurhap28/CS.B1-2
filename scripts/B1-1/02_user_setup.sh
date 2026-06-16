#!/bin/bash

source ../library.sh


# 02-1.
# 그룹(agent-core/common) 및 계정(agent-admin/dev/test) 생성
run_vm sudo groupadd agent-core
run_vm sudo groupadd agent-common

# 계정 생성 및 기본 로그인 쉘 지정 
run_vm sudo useradd -m -s /bin/bash agent-admin
run_vm sudo useradd -m -s /bin/bash agent-dev
run_vm sudo useradd -m -s /bin/bash agent-test

# 그룹에 계정을 할당
run_vm sudo usermod -aG agent-common agent-admin
run_vm sudo usermod -aG agent-common agent-dev
run_vm sudo usermod -aG agent-common agent-test
run_vm sudo usermod -aG agent-core agent-admin
run_vm sudo usermod -aG agent-core agent-dev

# 적용 확인
run_vm id agent-admin
run_vm id agent-dev
run_vm id agent-test

prompt_step "계정 및 그룹이 잘 생성되었는지 확인하세요."


# 02-2. 
# 디렉토리 구조 설정
run_vm sudo mkdir -p /home/agent-admin/agent-app/{upload_files,api_keys,bin}
run_vm sudo ls -la /home/agent-admin/agent-app
run_vm sudo mkdir -p /var/log/agent-app
run_vm sudo ls -ld /var/log/agent-app

prompt_step "디렉토리가 잘 생성되었는지 확인하세요."