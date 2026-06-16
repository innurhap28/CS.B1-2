#!/bin/bash

source ../library.sh


# 05-1. 
# monitor.sh 생성
run_vm sudo tee /home/agent-admin/agent-app/bin/monitor.sh > /dev/null << 'EOF'
#!/bin/bash
EOF

run_vm sudo bash /home/agent-admin/agent-app/bin/monitor.sh

prompt_step "monitor.sh이 정상적으로 출력되는지 확인하세요."

# 권한 설정
run_vm sudo chown agent-dev:agent-core /home/agent-admin/agent-app/bin/monitor.sh
run_vm sudo chmod 750 /home/agent-admin/agent-app/bin/monitor.sh

run_vm sudo chown -R root:agent-core /var/log/agent-app
run_vm sudo chmod 2770 /var/log/agent-app


# 05-2. 
# 자동 실행(cron) 설정
run_vm sudo -u agent-admin bash -c '(crontab -l 2>/dev/null; echo "* * * * * /home/agent-admin/agent-app/bin/monitor.sh") | crontab -'

run_vm sudo -u agent-admin crontab -l
prompt_step "Cron 등록이 되었는지 확인하세요."

echo ""
echo "monitor log 생성 확인까지 1분이 소요됩니다."

echo "Before:"
run_vm sudo wc -l /var/log/agent-app/monitor.log

echo ""
echo "1분 대기 중..."
sleep 65

echo ""
echo "After:"
run_vm sudo wc -l /var/log/agent-app/monitor.log

echo ""
echo "최근 로그:"
run_vm sudo tail -n 10 /var/log/agent-app/monitor.log

# 상태 겁증
run_vm pgrep -f agent-leak-app-x86 || echo "[FAIL] process"
run_vm sudo ss -tulnp | grep 15034 || echo "[FAIL] port"