#!/bin/sh
#########################################################
# 节点订阅自动获取脚本 - 并行模板版本
# 功能：自动查找可用的节点URL并生成订阅
# 特点：并行检测、超时控制、多模板支持
#########################################################

# ===== 日期处理函数 =====

# 获取当前日期（多种格式）
get_current_date() {
    # 完整日期（年月日）
    currentdate=$(date +%Y%m%d)
    currentyear=$(date +%Y)
    # 包含前导零的月份和日期
    currentmonth_padded=$(date +%m)
    currentday_padded=$(date +%d)
    # 不包含前导零的月份和日期
    currentmonth=$(echo "$currentmonth_padded" | sed 's/^0*//')
    currentday=$(echo "$currentday_padded" | sed 's/^0*//')
}

# 计算前N天的日期函数
calculate_previous_date() {
    days_to_subtract=$1
    # 在POSIX shell中使用不同的日期计算方法
    target_date=$(date -d "$currentyear-$currentmonth_padded-$currentday_padded -$days_to_subtract days" +"%Y %m %d %m %d" 2>/dev/null || echo "$currentyear $currentmonth_padded $currentday_padded $currentmonth $currentday")
    # 确保month_no_zero不包含前导零
    target_date_no_zero=$(echo "$target_date" | awk '{print $1 " " $2 " " $3 " " ($4 + 0) " " ($5 + 0)}')
    echo $target_date_no_zero
}

# ===== URL处理函数 =====

# URL解码函数
urldecode() {
    url_encoded="$1"
    # 替换+为空格
    url_encoded=$(echo "$url_encoded" | sed 's/+/ /g')
    # 解码%编码的字符
    printf '%b' "$(echo "$url_encoded" | sed 's/%/\\\\x/g')"
}

# URL编码函数（不依赖外部工具）
urlencode() {
    string="$1"
    strlen=$(echo "$string" | wc -c)
    strlen=$((strlen - 1))  # 减去换行符的长度
    
    encoded=""
    pos=0
    
    while [ $pos -lt $strlen ]; do
        pos=$((pos + 1))
        c=$(echo "$string" | cut -c$pos-$pos)
        case "$c" in
            [-_.~a-zA-Z0-9]) # 这些字符不需要编码
                encoded="$encoded$c"
                ;;
            *)
                # 将字符转换为十六进制
                hex=$(printf '%02x' "'$c" 2>/dev/null || printf '%%02x' "'$c")
                encoded="$encoded%$hex"
                ;;
        esac
    done
    echo "$encoded"
}

# 检查URL可用性
check_url_availability() {
    url="$1"
    # 使用curl检查URL是否可访问
    # -s: 静默模式，不显示进度
    # -L: 跟随重定向
    # -I: 只获取头信息
    # --connect-timeout 10: 连接超时10秒
    # --max-time 20: 总超时20秒
    status_code=$(curl -s -L -I --connect-timeout 10 --max-time 20 -o /dev/null -w '%{http_code}' "$url")
    
    # 检查状态码是否为200或30x（表示成功或重定向）
    case "$status_code" in
        200|30[0-9])
            return 0  # URL可用
            ;;
        *)
            return 1  # URL不可用
            ;;
    esac
}

# 检查单个模板的URL可用性
check_template_urls() {
    template_key="$1"
    template="$2"
    param1_type="$3"
    param2_type="$4"
    param3_type="$5"
    max_days_to_check=3  # 最多检查3天
    
    # 初始化日期变量
    year=$currentyear
    month_padded=$currentmonth_padded
    date_padded=$currentday_padded
    month_no_zero=$currentmonth
    date_no_zero=$currentday
    date_full="${year}${month_padded}${date_padded}"
    
    # 检查最近几天的URL (从当天开始)
    i=0
    while [ $i -lt $max_days_to_check ]; do
        # 计算日期 (当天及之前几天)
        if [ $i -gt 0 ]; then
            date_info=$(calculate_previous_date $i)
            year=$(echo $date_info | cut -d' ' -f1)
            month_padded=$(echo $date_info | cut -d' ' -f2)
            date_padded=$(echo $date_info | cut -d' ' -f3)
            month_no_zero=$(echo $date_info | cut -d' ' -f4)
            date_no_zero=$(echo $date_info | cut -d' ' -f5)
            date_full="${year}${month_padded}${date_padded}"
        fi
        
        # 根据参数类型选择对应的值
        check_param1=$year  # 年份总是相同格式
        
        # 处理月份参数
        case $param2_type in
            "month") check_param2=$month_padded ;;
            "month_no_zero") check_param2=$month_no_zero ;;
            "month_padded") check_param2=$month_padded ;;
            *) check_param2=$month_no_zero ;;  # 默认使用无前导零
        esac
        
        # 处理日期参数
        case $param3_type in
            "date") check_param3=$date_padded ;;
            "date_no_zero") check_param3=$date_no_zero ;;
            "date_padded") check_param3=$date_padded ;;
            "date_full") check_param3=$date_full ;;
            *) check_param3=$date_padded ;;  # 默认使用带前导零的日期
        esac
        
        # 使用printf格式化URL
        check_url=""
        # 特殊处理模板
        if [ "$template_key" = "3" ]; then
            # 模板3只需要一个date_full参数
            check_url=$(printf "$template" "$date_full")
        elif [ "$template_key" = "1" ] || [ "$template_key" = "2" ]; then
            # 模板1和2需要三个参数
            check_url=$(printf "$template" "$check_param1" "$check_param2" "$check_param3")
        else
            # 其他模板的处理逻辑
            if [ -z "$param2_type" ] && [ -z "$param3_type" ]; then
                # 只有一个参数的模板
                check_url=$(printf "$template" "$check_param3")
            elif [ -n "$param1_type" ] && [ -n "$param2_type" ] && [ -n "$param3_type" ]; then
                # 三个参数的模板
                check_url=$(printf "$template" "$check_param1" "$check_param2" "$check_param3")
            elif [ -n "$param1_type" ] && [ -n "$param2_type" ] && [ -z "$param3_type" ]; then
                # 两个参数的模板
                check_url=$(printf "$template" "$check_param1" "$check_param2")
            else
                # 默认处理方式
                check_url=$(printf "$template" "$check_param3")
            fi
        fi
        
        # 添加调试信息
        echo "正在检查URL: $check_url (模板 $template_key, 第 $i 天)" >&2
        
        if check_url_availability "$check_url"; then
            echo "$check_url"
            return 0
        fi
        
        # 每检查5天打印一次进度
        remainder=$(( (i+1) % 5 ))
        if [ $remainder -eq 0 ]; then
            echo "已检查 $((i+1)) 天，继续搜索..." >&2
        fi
        
        i=$((i + 1))
    done
    
    # 如果没有找到有效的URL，返回空
    return 1
}

# ===== 主程序 =====

# 初始化日期变量
get_current_date

# 定义URL模板结构体
# 格式: "URL模板|年份参数类型|月份参数类型|日期参数类型"
templates="https://a.nodeshare.xyz/uploads/%s/%s/%s.yaml|year|month_no_zero|date_full
https://nodefree.githubrowcontent.com/%s/%s/%s.yaml|year|month_padded|date_full
https://free.datiya.com/uploads/%s-clash.yaml|date_full
https://fastly.jsdelivr.net/gh/ripaojiedian/freenode@main/clash
https://www.xrayvip.com/free.yaml
https://ghproxy.net/https://raw.githubusercontent.com/anaer/Sub/main/clash.yaml
https://ghproxy.net/https://raw.githubusercontent.com/Pawdroid/Free-servers/main/sub
https://fastly.jsdelivr.net/gh/zhangkaiitugithub/passcro@main/speednodes.yaml
https://raw.githubusercontent.com/ermaozi/get_subscribe/main/subscribe/clash.yml
https://raw.githubusercontent.com/go4sharing/sub/main/sub.yaml
https://raw.githubusercontent.com/Jsnzkpg/Jsnzkpg/Jsnzkpg/Jsnzkpg
https://raw.githubusercontent.com/ermaozi01/free_clash_vpn/main/subscribe/clash.yml
https://fpyjdy.zzong6599.workers.dev
https://rss.zyfx6.xyz/clash"

# 用于存储每个模板找到的可用URL
template_valid_urls=""

echo "========== 开始查找可用节点 =========="

# 创建临时文件存储并行任务结果
temp_file=$(mktemp)

# 并行检查所有模板
i=1
# 创建一个临时目录来存储各个任务的结果
result_dir=$(mktemp -d 2>/dev/null || mktemp -d ./temp_XXXXXX 2>/dev/null || echo "./temp_$$")
mkdir -p "$result_dir" 2>/dev/null

echo "$templates" | while IFS= read -r template_info; do
    # 如果到达最后一行（空行），则跳出循环
    if [ -z "$template_info" ]; then
        break
    fi
    
    template=$(echo "$template_info" | cut -d'|' -f1)
    param1_type=$(echo "$template_info" | cut -d'|' -f2)
    param2_type=$(echo "$template_info" | cut -d'|' -f3)
    param3_type=$(echo "$template_info" | cut -d'|' -f4)
    
    # 后台运行检查，结果写入独立的临时文件
    (
        result=$(check_template_urls "$i" "$template" "$param1_type" "$param2_type" "$param3_type")
        result_file="${result_dir}/${i}"
        # 确保结果文件的目录存在
        mkdir -p "$(dirname "$result_file")" 2>/dev/null
        if [ -n "$result" ]; then
            echo "${i}|${result}" > "$result_file"
            echo "检测到有效URL (模板[$i]): $result" >&2
        else
            echo "$i|未找到可用URL" > "$result_file"
            echo "模板[$i] 未找到有效URL" >&2
        fi
    ) &
    
    i=$((i + 1))
done

# 等待所有后台进程完成
wait

# 合并所有结果文件到一个临时文件（按数字顺序）
template_count=$(echo "$templates" | grep -v '^$' | wc -l | tr -d ' ')
for i in $(seq 1 $template_count); do
    result_file="${result_dir}/${i}"
    if [ -f "$result_file" ]; then
        cat "$result_file" >> "$temp_file"
    fi
done

# 清理临时目录
rm -rf "$result_dir"

# 从临时文件加载结果（按模板编号顺序）
# 创建一个关联数组来存储结果
url_count=$(echo "$templates" | grep -v '^$' | wc -l | tr -d ' ')
template_results=""

while IFS="|" read -r template_key result; do
    if [ -n "$template_key" ]; then
        # 将结果存储在以模板编号为索引的变量中
        eval "template_result_$template_key=\"$result\""
    fi
done < "$temp_file"
rm -f "$temp_file"

# 按顺序构建template_valid_urls
for i in $(seq 1 $url_count); do
    eval "result=\"\$template_result_$i\""
    if [ -n "$result" ] && [ "$result" != "未找到可用URL" ]; then
        if [ -z "$template_valid_urls" ]; then
            template_valid_urls="$result"
        else
            template_valid_urls="$template_valid_urls|$result"
        fi
    fi
done

echo "========== URL查找完成 =========="

# 统计找到的可用URL数量
url_count=$(echo "$templates" | grep -v '^$' | wc -l | tr -d ' ')

# 检查template_valid_urls中有效URL的数量
if [ -n "$template_valid_urls" ]; then
    # 计算有效URL的数量（不包含"未找到可用URL"的条目）
    found_count=$(echo "$template_valid_urls" | tr '|' '\n' | grep -v "未找到可用URL" | grep -v "^$" | wc -l)
else
    found_count=0
fi

# 确保found_count不会为负数
if [ $found_count -lt 0 ]; then
    found_count=0
fi

# 生成默认URL的函数
generate_default_url() {
    template="$1"
    param1_type="$2"
    param2_type="$3"
    param3_type="$4"
    template_index="$5"
    
    # 使用当天日期生成默认URL
    date_full_default="${currentyear}${currentmonth_padded}${currentday_padded}"
    
    # 根据模板参数数量和类型生成默认URL
    url=""
    case $template_index in
        1)
            # 模板1: https://a.nodeshare.xyz/uploads/%s/%s/%s.yaml|year|month_no_zero|date_full
            url=$(printf "$template" "$currentyear" "$currentmonth" "$date_full_default")
            echo "生成模板1的URL: $url" >&2
            ;;
        2)
            # 模板2: https://nodefree.githubrowcontent.com/%s/%s/%s.yaml|year|month_padded|date_full
            url=$(printf "$template" "$currentyear" "$currentmonth_padded" "$date_full_default")
            echo "生成模板2的URL: $url" >&2
            ;;
        3)
            # 模板3: https://free.datiya.com/uploads/%s-clash.yaml|date_full
            url=$(printf "$template" "$date_full_default")
            echo "生成模板3的URL: $url" >&2
            ;;
        4)
            # 模板4: https://fastly.jsdelivr.net/gh/ripaojiedian/freenode@main/clash (无参数)
            url="$template"
            ;;
        7)
            # 模板7: https://ghproxy.net/https://raw.githubusercontent.com/Pawdroid/Free-servers/main/sub (无参数)
            url="$template"
            ;;
        *)
            # 处理其他模板 - 对于只有一个参数的模板
            if [ -z "$param2_type" ] && [ -z "$param3_type" ]; then
                # 只有一个参数的模板，尝试用日期参数
                url=$(printf "$template" "$date_full_default")
            elif [ -n "$param1_type" ] && [ -n "$param2_type" ] && [ -n "$param3_type" ]; then
                # 三个参数的模板
                # 处理年份参数
                case $param1_type in
                    "year") param1_val="$currentyear" ;;
                    *) param1_val="$currentyear" ;;
                esac
                
                # 处理月份参数
                case $param2_type in
                    "month") param2_val="$currentmonth_padded" ;;
                    "month_no_zero") param2_val="$currentmonth" ;;
                    "month_padded") param2_val="$currentmonth_padded" ;;
                    *) param2_val="$currentmonth" ;;
                esac
                
                # 处理日期参数
                case $param3_type in
                    "date") param3_val="$currentday_padded" ;;
                    "date_no_zero") param3_val="$currentday" ;;
                    "date_padded") param3_val="$currentday_padded" ;;
                    "date_full") param3_val="$date_full_default" ;;
                    *) param3_val="$date_full_default" ;;
                esac
                
                url=$(printf "$template" "$param1_val" "$param2_val" "$param3_val")
            elif [ -n "$param1_type" ] && [ -n "$param2_type" ] && [ -z "$param3_type" ]; then
                # 两个参数的模板
                # 处理第一个参数
                case $param1_type in
                    "year") param1_val="$currentyear" ;;
                    *) param1_val="$currentyear" ;;
                esac
                
                # 处理第二个参数
                case $param2_type in
                    "month") param2_val="$currentmonth_padded" ;;
                    "month_no_zero") param2_val="$currentmonth" ;;
                    "month_padded") param2_val="$currentmonth_padded" ;;
                    "date_full") param2_val="$date_full_default" ;;
                    *) param2_val="$date_full_default" ;;
                esac
                
                url=$(printf "$template" "$param1_val" "$param2_val")
            fi
            ;;
    esac
    
    echo "$url"
}

# 如果没有找到有效的URL，则使用默认URL
if [ $found_count -eq 0 ] || [ -z "$template_valid_urls" ]; then
    echo "未找到任何有效URL，使用默认URL"
    i=1
    echo "$templates" | while IFS= read -r template_info; do
        # 如果到达最后一行（空行），则跳出循环
        if [ -z "$template_info" ]; then
            break
        fi
        
        template=$(echo "$template_info" | cut -d'|' -f1)
        param1_type=$(echo "$template_info" | cut -d'|' -f2)
        param2_type=$(echo "$template_info" | cut -d'|' -f3)
        param3_type=$(echo "$template_info" | cut -d'|' -f4)
            
        # 生成默认URL
        url=$(generate_default_url "$template" "$param1_type" "$param2_type" "$param3_type" "$i")
            
        # 保存URL
        if [ -n "$url" ]; then
            # 使用逗号分隔的方式存储结果
            if [ -z "$template_valid_urls" ] || [ "$template_valid_urls" = "未找到可用URL" ]; then
                template_valid_urls="$url"
            else
                template_valid_urls="$template_valid_urls|$url"
            fi
        fi
            
        i=$((i + 1))
    done
else
    # 显示最终使用的URL
    i=1
    echo "$template_valid_urls" | tr '|' '\n' | while IFS= read -r url_value; do
        if [ -n "$url_value" ] && [ "$url_value" != "未找到可用URL" ]; then
            echo "使用模板[$i]: $url_value"
        fi
        i=$((i + 1))
    done
fi

# 设置valid_urls为template_valid_urls
valid_urls="$template_valid_urls"

# 使用管道符号(|)连接所有有效URL
combined_urls="$valid_urls"
echo "合并URL: $combined_urls"

# 对combined_urls进行URL编码
encoded_combined_urls=$(urlencode "$combined_urls")
echo "编码后URL: $encoded_combined_urls"

# 构建订阅链接
echo "========== 生成订阅链接 =========="
subscribeclash="https://api.v1.mk/sub?target=clash&url=$encoded_combined_urls&insert=false&config=https%3A%2F%2Fraw.githubusercontent.com%2Fzsokami%2FACL4SSR%2Frefs%2Fheads%2Fmain%2FACL4SSR_Online_Full_Mannix_No_DNS_Leak.ini&exclude=聖荷西&filename=GitHub-GetNode&emoji=true&sort=true&udp=true"
subscribeV2ray="https://api.v1.mk/sub?target=v2ray&url=$encoded_combined_urls&insert=false&config=https%3A%2F%2Fraw.githubusercontent.com%2Fzsokami%2FACL4SSR%2Frefs%2Fheads%2Fmain%2FACL4SSR_Online_Full_Mannix_No_DNS_Leak.ini&exclude=聖荷西&filename=GitHub-GetNode&emoji=true&sort=true&udp=true"

# 打印完整的订阅链接参数
echo "========== 订阅链接详情 =========="
echo "Clash订阅链接:"
echo "$subscribeclash" | fold -w 80

# 解析并打印订阅链接的各个参数
echo ""
echo "订阅链接参数解析:"
echo "- 目标格式: clash"
echo "- 源URL列表: "

# 显示所有有效的URL
valid_url_count=0
if [ -n "$template_valid_urls" ]; then
    echo "$template_valid_urls" | tr '|' '\n' | grep -v "未找到可用URL" | grep -v "^$" | while IFS= read -r url_value; do
        if [ -n "$url_value" ]; then
            echo "  * $url_value"
            valid_url_count=$((valid_url_count + 1))
        fi
    done
else
    valid_url_count=0
fi

# 如果template_valid_urls为空，则设置valid_url_count为0
if [ -z "$template_valid_urls" ]; then
    valid_url_count=0
fi

# 如果没有找到任何有效URL，显示提示信息
if [ $valid_url_count -eq 0 ]; then
    echo "  * 未找到有效URL"
fi

# 解码配置URL
config_encoded="https%3A%2F%2Fraw.githubusercontent.com%2FNZESupB%2FProfile%2Fmain%2Foutpref%2Fpypref%2Fpyfull.ini"
config_decoded=$(urldecode "$config_encoded")
echo "- 配置文件: $config_decoded"

echo "- 文件名: GitHub-GetNode"
echo "- 其他参数:"
echo "  * emoji: true (添加Emoji图标)"
echo "  * sort: true (节点排序)"
echo "  * udp: true (启用UDP转发)"

# 保存订阅链接到文件
echo "$subscribeclash" > ./clash_subscribe_url.txt
echo "Clash订阅链接已保存到 clash_subscribe_url.txt"
echo ""

# 删除旧文件
if [ -f "./clash.yaml" ]; then
    rm -f ./clash.yaml
    echo "已删除旧的clash.yaml文件"
fi
if [ -f "./v2ray.txt" ]; then
    rm -f ./v2ray.txt
    echo "已删除旧的v2ray.txt文件"
fi

# 下载订阅
echo "========== 下载订阅文件 =========="
echo "下载Clash配置..."
if wget --timeout=30 --tries=2 --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" -q "$subscribeclash" -O ./clash.yaml; then
    echo "Clash配置下载成功"
else
    echo "Clash配置下载失败，退出码: $?"
    # 尝试显示更多错误信息
    wget --timeout=30 --tries=1 --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" -S "$subscribeclash" -O ./clash.yaml 2>&1 | head -20
fi

echo "下载V2Ray配置..."
if wget --timeout=30 --tries=2 --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" -q "$subscribeV2ray" -O ./v2ray.txt; then
    echo "V2Ray配置下载成功"
else
    echo "V2Ray配置下载失败，退出码: $?"
    # 尝试显示更多错误信息
    wget --timeout=30 --tries=1 --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" -S "$subscribeV2ray" -O ./v2ray.txt 2>&1 | head -20
fi

# 处理下载的clash.yaml文件
echo "========== 处理clash.yaml文件 =========="
# 创建临时文件
temp_file=$(mktemp)

# 初始化状态变量
in_proxy=0
in_proxy_groups=0
in_current_proxy=0
in_proxies_list=0
in_url_test_group=0
remove_current=0
current_server=""
current_port=""
proxy_content=""
servers_seen=""
valid_names=""
deleted_names=""
current_group_name=""
current_group_type=""

# 逐行处理clash.yaml文件
while IFS= read -r line; do
    # 检查是否是proxies部分开始
    if echo "$line" | grep -q "^proxies:$"; then
        in_proxy=1
        in_proxy_groups=0
        in_proxies_list=0
        in_url_test_group=0
        echo "$line"
        continue
    fi
    
    # 检查是否是proxy-groups部分开始
    if echo "$line" | grep -q "^proxy-groups:$"; then
        in_proxy=0
        in_proxy_groups=1
        in_proxies_list=0
        in_url_test_group=0
        echo "$line"
        # 输出删除的节点名称用于调试
        continue
    fi
    
    # 处理proxies部分
    if [ $in_proxy -eq 1 ]; then
        # 检查是否是新节点开始
        if echo "$line" | grep -q "^  - "; then
            # 处理上一个节点（如果存在）
            if [ $in_current_proxy -eq 1 ]; then
                if [ $remove_current -eq 0 ]; then
                    # 检查是否已存在相同server和port的节点
                    is_duplicate=0
                    if [ -n "$current_server" ] && [ -n "$current_port" ]; then
                        if echo " $servers_seen " | grep -q " $current_server:$current_port "; then
                            is_duplicate=1
                        fi
                    fi
                    
                    if [ $is_duplicate -eq 0 ]; then
                        # server和port未同时出现过，输出节点
                        echo "$proxy_content"
                        # 记录server:port组合
                        if [ -n "$current_server" ] && [ -n "$current_port" ]; then
                            servers_seen="$servers_seen $current_server:$current_port"
                        fi
                        # 记录有效的节点名称
                        name_match=$(echo "$proxy_content" | grep -o "name: [^,}]*" | head -1)
                        if echo "$name_match" | grep -q "name:"; then
                            node_name=$(echo "$name_match" | cut -d" " -f2-)
                            # 使用引号包围节点名称以处理特殊字符
                            valid_names="$valid_names \"$node_name\""
                        fi
                    else
                        # 记录被删除的重复节点名称
                        name_match=$(echo "$proxy_content" | grep -o "name: [^,}]*" | head -1)
                        if echo "$name_match" | grep -q "name:"; then
                            node_name=$(echo "$name_match" | cut -d" " -f2-)
                            # 使用引号包围节点名称以处理特殊字符
                            deleted_names="$deleted_names \"$node_name\""
                        fi
                    fi
                else
                    # 记录被删除的无效节点名称
                    name_match=$(echo "$proxy_content" | grep -o "name: [^,}]*" | head -1)
                    if echo "$name_match" | grep -q "name:"; then
                        node_name=$(echo "$name_match" | cut -d" " -f2-)
                        # 使用引号包围节点名称以处理特殊字符
                        deleted_names="$deleted_names \"$node_name\""
                    fi
                fi
            fi
            
            # 重置状态以处理新节点
            in_current_proxy=1
            proxy_content="$line"
            current_server=""
            current_port=""
            remove_current=0
            
            # 检查是否包含 cipher: "" 或 password: ""
            if echo "$line" | grep -q "cipher: \"\"" || echo "$line" | grep -q "password: \"\""; then
                remove_current=1
            fi
            
            # 尝试提取server和port
            server_match=$(echo "$line" | grep -o "server: [^,}]*" | head -1)
            if echo "$server_match" | grep -q "server:"; then
                current_server=$(echo "$server_match" | cut -d" " -f2)
            fi
            port_match=$(echo "$line" | grep -o "port: [^,}]*" | head -1)
            if echo "$port_match" | grep -q "port:"; then
                current_port=$(echo "$port_match" | cut -d" " -f2)
            fi
            continue
        fi
        
        # 在节点内容中
        if [ $in_current_proxy -eq 1 ]; then
            proxy_content="$proxy_content
$line"
            
            # 继续检查是否需要删除当前节点
            if [ $remove_current -eq 0 ]; then
                if echo "$line" | grep -q "cipher: \"\"" || echo "$line" | grep -q "password: \"\""; then
                    remove_current=1
                fi
            fi
            
            # 继续尝试提取server和port
            if [ -z "$current_server" ]; then
                server_match=$(echo "$line" | grep -o "server: [^,}]*" | head -1)
                if echo "$server_match" | grep -q "server:"; then
                    current_server=$(echo "$server_match" | cut -d" " -f2)
                fi
            fi
            if [ -z "$current_port" ]; then
                port_match=$(echo "$line" | grep -o "port: [^,}]*" | head -1)
                if echo "$port_match" | grep -q "port:"; then
                    current_port=$(echo "$port_match" | cut -d" " -f2)
                fi
            fi
            continue
        fi
        
        # proxies部分结束
        if echo "$line" | grep -q "^[^ ]" && ! echo "$line" | grep -q "^ "; then
            # 处理最后一个节点
            if [ $in_current_proxy -eq 1 ] && [ $remove_current -eq 0 ]; then
                # 检查是否已存在相同server和port的节点
                is_duplicate=0
                if [ -n "$current_server" ] && [ -n "$current_port" ]; then
                    if echo " $servers_seen " | grep -q " $current_server:$current_port "; then
                        is_duplicate=1
                    fi
                fi
                
                if [ $is_duplicate -eq 0 ]; then
                    # server和port未同时出现过，输出节点
                    echo "$proxy_content"
                    # 记录server:port组合
                    if [ -n "$current_server" ] && [ -n "$current_port" ]; then
                        servers_seen="$servers_seen $current_server:$current_port"
                    fi
                    # 记录有效的节点名称
                    name_match=$(echo "$proxy_content" | grep -o "name: [^,}]*" | head -1)
                    if echo "$name_match" | grep -q "name:"; then
                        node_name=$(echo "$name_match" | cut -d" " -f2-)
                        # 使用引号包围节点名称以处理特殊字符
                        valid_names="$valid_names \"$node_name\""
                    fi
                else
                    # 记录被删除的重复节点名称
                    name_match=$(echo "$proxy_content" | grep -o "name: [^,}]*" | head -1)
                    if echo "$name_match" | grep -q "name:"; then
                        node_name=$(echo "$name_match" | cut -d" " -f2-)
                        # 使用引号包围节点名称以处理特殊字符
                        deleted_names="$deleted_names \"$node_name\""
                    fi
                fi
            elif [ $in_current_proxy -eq 1 ] && [ $remove_current -eq 1 ]; then
                # 记录被删除的无效节点名称
                name_match=$(echo "$proxy_content" | grep -o "name: [^,}]*" | head -1)
                if echo "$name_match" | grep -q "name:"; then
                    node_name=$(echo "$name_match" | cut -d" " -f2-)
                    # 使用引号包围节点名称以处理特殊字符
                    deleted_names="$deleted_names \"$node_name\""
                fi
            fi
            
            # 结束proxies部分处理
            in_proxy=0
            in_current_proxy=0
            echo "$line"
            continue
        fi
        
        # proxies部分的其他行
        echo "$line"
        continue
    fi
    
    # 处理proxy-groups部分
    if [ $in_proxy_groups -eq 1 ]; then
        # 检查是否是新的group开始 (以两个空格开头后跟字母)
        if echo "$line" | grep -q "^  [a-zA-Z]"; then
            # 重置状态变量
            in_proxies_list=0
            in_url_test_group=0
            current_group_type=""
            # 注意：不要在这里重置current_group_name，因为name行可能在type行之后出现
            echo "DEBUG: 检测到新的proxy-group开始" >&2
            echo "$line"
            continue
        fi
        
        # 获取当前group的名称
        if echo "$line" | grep -q "^  - name:"; then
            # 直接替换掉"  - name: "前缀来获取名称
            current_group_name=$(echo "$line" | sed 's/  - name: *//')
            # 去除可能存在的前后引号和尾部空格
            current_group_name=$(echo "$current_group_name" | sed 's/^"\(.*\)"$/\1/' | sed 's/[[:space:]]*$//')
            echo "DEBUG: 当前group名称: $current_group_name" >&2
            echo "$line"
            continue
        fi
        
        # 检查group类型
        if echo "$line" | grep -q "^    type: url-test"; then
            in_url_test_group=1
            current_group_type="url-test"
            echo "DEBUG: 检测到url-test类型的group" >&2
            echo "$line"
            continue
        fi
        
        # 检查是否是proxies列表开始
        if echo "$line" | grep -q "^    proxies:$"; then
            in_proxies_list=1
            echo "DEBUG: 进入proxies列表，当前group类型: $current_group_type" >&2
            echo "$line"
            continue
        fi
        
        # 定义需要检查节点有效性的proxy-group名称集合
        special_group_names="\"⚡ ‍低延迟\" \"👆🏻 ‍指定\" \"🇭🇰 ‍香港\" \"🇹🇼 ‍台湾\" \"🇨🇳 ‍中国\" \"🇸🇬 ‍新加坡\" \"🇯🇵 ‍日本\" \"🇺🇸 ‍美国\" \"🎏 ‍其他\" \"👆🏻🇭🇰 ‍香港\" \"👆🏻🇹🇼 ‍台湾\" \"👆🏻🇨🇳 ‍中国\" \"👆🏻🇸🇬 ‍新加坡\" \"👆🏻🇯🇵 ‍日本\" \"👆🏻🇺🇸 ‍美国\" \"👆🏻🎏 ‍其他\""
        
        # 如果在proxies列表中
        if [ "$in_proxies_list" = "1" ]; then
            # 检查是否是proxies列表条目 (以"      - "开头)
            if echo "$line" | grep -q "^      - "; then
                # 提取proxy名称
                proxy_name=""
                if echo "$line" | grep -q "^      - [^{]"; then
                    # 处理普通格式: "      - ProxyName"
                    # 使用更简单直接的方法提取节点名称，保留完整内容包括空格和特殊字符
                    proxy_name=$(echo "$line" | sed 's/^      - //' | sed 's/ *#.*//' | sed 's/ *$//')
                elif echo "$line" | grep -q "^      -{name:"; then
                    # 处理内联格式: "      - {name: ProxyName, ...}"
                    name_match=$(echo "$line" | grep -o "name: [^,}]*" | head -1)
                    proxy_name=$(echo "$name_match" | cut -d" " -f2-)
                fi
                
                # 添加调试日志
                echo "DEBUG: 处理组中的节点引用: '$proxy_name'" >&2
                echo "DEBUG: 当前group类型: $current_group_type" >&2
                echo "DEBUG: 当前group名称: $current_group_name" >&2
                echo "DEBUG: 当前有效节点列表: $valid_names" >&2
                
                # 检查是否需要验证节点有效性
                need_check_validity=0
                
                # 对于url-test类型的group，需要检查节点有效性
                if [ "$in_url_test_group" = "1" ]; then
                    need_check_validity=1
                    echo "DEBUG: url-test组，需要检查节点有效性" >&2
                # 对于非url-test类型但name在指定集合中的group，需要检查节点有效性
                elif echo " $special_group_names " | grep -q " \"$current_group_name\" "; then
                    need_check_validity=1
                    echo "DEBUG: 特殊名称组，需要检查节点有效性" >&2
                else
                    echo "DEBUG: 普通组，不需要检查节点有效性" >&2
                fi
                
                # 如果需要检查节点有效性
                if [ "$need_check_validity" = "1" ]; then
                    if [ -n "$proxy_name" ]; then
                        # 检查是否在有效节点列表中，使用引号包围确保精确匹配
                        if echo " $valid_names " | grep -q " \"$proxy_name\" "; then
                            echo "DEBUG: 保留有效的节点引用: '$proxy_name'" >&2
                            echo "$line"
                        else
                            echo "DEBUG: 移除无效的节点引用: '$proxy_name'" >&2
                            # 真正跳过输出该行
                            continue
                        fi
                        continue
                    fi
                    echo "DEBUG: proxy_name为空，直接输出行内容" >&2
                    echo "$line"
                else
                    # 不需要检查节点有效性，直接输出
                    echo "$line"
                fi
                continue
            else
                echo "DEBUG: 不是proxies列表条目，检查是否需要重置状态" >&2
                echo "DEBUG: 当前行内容: $line" >&2
                # 不是proxies列表条目，可能是结束或其他属性
                # 重置proxies列表标记
                if echo "$line" | grep -q "^    [a-zA-Z]"; then
                    echo "DEBUG: 检测到属性行，重置proxies列表状态" >&2
                    in_proxies_list=0
                    in_url_test_group=0
                fi
            fi
            echo "$line"
            continue
        fi

        # 输出其他行
        echo "$line"
        continue
    fi
    
    # 处理其他部分
    echo "$line"
done < ./clash.yaml > "$temp_file"

# 移动临时文件到原文件
mv "$temp_file" ./clash.yaml
echo "Clash配置已清理完成"

echo "========== 任务完成 =========="
echo "生成的文件:"
echo "1. clash.yaml - Clash配置文件"
echo "2. v2ray.txt - V2Ray配置文件"
echo "3. clash_subscribe_url.txt - Clash订阅链接"
echo ""
echo "可以使用以下命令查看完整的订阅链接:"
echo "cat ./clash_subscribe_url.txt"
