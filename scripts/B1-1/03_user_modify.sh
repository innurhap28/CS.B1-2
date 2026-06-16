#!/bin/bash

source ../library.sh


# 03-1.
# 디렉토리 권한 기본 설정

# 기본 소유권 설정
run_vm sudo chown -R agent-admin:agent-common /home/agent-admin/agent-app
run_vm sudo chown -R agent-admin:agent-core /home/agent-admin/agent-app/api_keys
run_vm sudo chown -R agent-dev:agent-core /home/agent-admin/agent-app/bin
run_vm sudo chown -R agent-admin:agent-core /var/log/agent-app

# 기본 권한 설정
# setgid bit을 설정하여 새 파일 생성 시 그룹 자동 상속
run_vm sudo chmod 2770 /home/agent-admin/agent-app/upload_files
run_vm sudo chmod 2770 /home/agent-admin/agent-app/api_keys
run_vm sudo chmod 2770 /home/agent-admin/agent-app/bin
run_vm sudo chmod 2770 /var/log/agent-app

run_vm sudo ls -la /home/agent-admin/agent-app
run_vm sudo ls -ld /var/log/agent-app

prompt_step "디렉토리 소유권 및 권한이 잘 설정되었는지 확인하세요"


# 03-2.
# ACL 설정
run_vm sudo setfacl -R -m g:agent-common:rwx /home/agent-admin/agent-app/upload_files
run_vm sudo setfacl -R -d -m g:agent-common:rwx /home/agent-admin/agent-app/upload_files

run_vm sudo setfacl -R -m g:agent-core:rwx /home/agent-admin/agent-app/api_keys
run_vm sudo setfacl -R -d -m g:agent-core:rwx /home/agent-admin/agent-app/api_keys

run_vm sudo setfacl -R -m g:agent-core:rwx /home/agent-admin/agent-app/bin
run_vm sudo setfacl -R -d -m g:agent-core:rwx /home/agent-admin/agent-app/bin

run_vm sudo setfacl -R -m g:agent-core:rwx /var/log/agent-app
run_vm sudo setfacl -R -d -m g:agent-core:rwx /var/log/agent-app

# ACL 확인
run_vm sudo getfacl /home/agent-admin/agent-app/upload_files
prompt_step "ACL이 잘 적용되었는지 확인하세요."