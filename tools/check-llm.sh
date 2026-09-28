#!/usr/bin/env bash
# 檢查 .70 / .103 上跑什麼模型、用什麼 GPU
# 需在公司內網、且有 connect-xcloud-servers skill 的機器上執行
#
#   bash tools/check-llm.sh          # 兩台都查
#   bash tools/check-llm.sh 70       # 只查 .70

XSSH="$HOME/.claude/skills/connect-xcloud-servers/scripts/xssh.sh"
[[ -f "$XSSH" ]] || { echo "找不到 $XSSH"; exit 1; }
if [[ $# -gt 0 ]]; then HOSTS=("$@"); else HOSTS=(70 103); fi

run() { bash "$XSSH" "$1" "$2" 2>&1; }

for h in "${HOSTS[@]}"; do
cat <<EOF

================================================================
                              .$h
================================================================
EOF

echo "----- [1] GPU 硬體 -----"
run "$h" 'nvidia-smi --query-gpu=index,name,memory.total,memory.used,utilization.gpu,temperature.gpu,driver_version --format=csv 2>/dev/null || echo "(無 nvidia-smi)"'

echo
echo "----- [2] 佔用 GPU 的行程 -----"
run "$h" 'nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv 2>/dev/null || echo "(無)"'

echo
echo "----- [3] Ollama 已安裝模型 -----"
run "$h" 'command -v ollama >/dev/null && ollama list || curl -s --max-time 3 localhost:11434/api/tags || echo "(無 Ollama)"'

echo
echo "----- [4] Ollama 目前載入 VRAM 的模型 -----"
run "$h" 'command -v ollama >/dev/null && ollama ps || echo "(無)"'

echo
echo "----- [5] OpenAI 相容 API (vLLM / LM Studio / llama.cpp) -----"
run "$h" 'for p in 8000 8080 1234 5000 9997 30000; do
  r=$(curl -s --max-time 2 "http://localhost:$p/v1/models" 2>/dev/null)
  [ -n "$r" ] && echo "  [port $p] $r"
done; true'

echo
echo "----- [6] 執行中的 AI 容器 -----"
run "$h" 'docker ps --format "  {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "(無 docker 權限)"'

echo
echo "----- [7] 相關 systemd 服務 -----"
run "$h" 'systemctl list-units --type=service --state=running --no-pager 2>/dev/null | grep -iE "ollama|vllm|llama|triton|tgi|xinference|comfy|webui" || echo "(無)"'

echo
echo "----- [8] 監聽中的埠 -----"
run "$h" 'ss -tlnp 2>/dev/null | grep -vE "127.0.0.1|::1" | head -25 || netstat -tlnp 2>/dev/null | head -25'

echo
echo "----- [9] 主機基本資訊 -----"
run "$h" 'echo "  hostname: $(hostname)"; echo "  os      : $(. /etc/os-release 2>/dev/null; echo $PRETTY_NAME)"; echo "  kernel  : $(uname -r)"; echo "  cpu     : $(nproc) cores"; echo "  ram     : $(free -g 2>/dev/null | awk "/Mem:/{print \$2\" GB\"}")"; echo "  cuda    : $(nvcc --version 2>/dev/null | grep release || echo n/a)"'
done
echo
