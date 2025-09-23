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
    
    # 确保日期部分始终为两位数
    if [ -z "$currentday" ]; then
        currentday="0"
    fi
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
    # --connect-timeout 20: 连接超时20秒（从15秒增加到20秒）
    # --max-time 45: 总超时45秒（从30秒增加到45秒）
    status_code=$(curl -s -L -I --connect-timeout 20 --max-time 45 -o /dev/null -w '%{http_code}' "$url")
    
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
    max_days_to_check=7  # 最多检查7天
    
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
url_template_1="https://a.nodeshare.xyz/uploads/%s/%s/%s.yaml|year|month_no_zero|date_full"
url_template_2="https://nodefree.githubrowcontent.com/%s/%s/%s.yaml|year|month_padded|date_full"
url_template_3="https://free.datiya.com/uploads/%s-clash.yaml|date_full"
url_template_4="https://fastly.jsdelivr.net/gh/ripaojiedian/freenode@main/clash"
url_template_5="https://www.xrayvip.com/free.yaml"
url_template_6="https://ghproxy.net/https://raw.githubusercontent.com/anaer/Sub/main/clash.yaml"
url_template_7="https://ghproxy.net/https://raw.githubusercontent.com/Pawdroid/Free-servers/main/sub"
url_template_8="https://fastly.jsdelivr.net/gh/zhangkaiitugithub/passcro@main/speednodes.yaml"
url_template_9="https://raw.githubusercontent.com/ermaozi/get_subscribe/main/subscribe/clash.yml"
url_template_10="https://raw.githubusercontent.com/go4sharing/sub/main/sub.yaml"
url_template_11="https://raw.githubusercontent.com/Jsnzkpg/Jsnzkpg/Jsnzkpg/Jsnzkpg"
url_template_12="https://raw.githubusercontent.com/ermaozi01/free_clash_vpn/main/subscribe/clash.yml"

# 用于存储每个模板找到的可用URL
template_valid_urls_1=""
template_valid_urls_2=""
template_valid_urls_3=""
template_valid_urls_4=""
template_valid_urls_5=""
template_valid_urls_6=""
template_valid_urls_7=""
template_valid_urls_8=""
template_valid_urls_9=""
template_valid_urls_10=""
template_valid_urls_11=""
template_valid_urls_12=""

echo "========== 开始查找可用节点 =========="

# 创建临时文件存储并行任务结果
temp_file=$(mktemp)

# 并行检查所有模板
i=1
while [ $i -le 12 ]; do
    # 解析模板和参数
    eval "template_info=\$url_template_$i"
    template=$(echo "$template_info" | cut -d'|' -f1)
    param1_type=$(echo "$template_info" | cut -d'|' -f2)
    param2_type=$(echo "$template_info" | cut -d'|' -f3)
    param3_type=$(echo "$template_info" | cut -d'|' -f4)
    
    # 后台运行检查，结果写入临时文件
    (
        result=$(check_template_urls "$i" "$template" "$param1_type" "$param2_type" "$param3_type")
        if [ -n "$result" ]; then
            echo "${i}|${result}" >> "$temp_file"
            echo "检测到有效URL (模板[$i]): $result" >&2
        else
            echo "$i|未找到可用URL" >> "$temp_file"
            echo "模板[$i] 未找到有效URL" >&2
        fi
    ) &
    
    i=$((i + 1))
done

# 等待所有后台进程完成
wait

# 从临时文件加载结果
while IFS="|" read -r template_key result; do
    if [ "$result" != "未找到可用URL" ]; then
        eval "template_valid_urls_${template_key}=\"$result\""
    fi
done < "$temp_file"
rm -f "$temp_file"

echo "========== URL查找完成 =========="

# 统计找到的可用URL数量
found_count=0
i=1
while [ $i -le 12 ]; do
    eval "url_value=\$template_valid_urls_${i}"
    if [ -n "$url_value" ]; then
        found_count=$((found_count + 1))
    fi
    i=$((i + 1))
done

# 如果所有模板都未找到可用URL，才使用默认URL
if [ $found_count -eq 0 ]; then
    echo "警告: 所有模板均未找到可用URL，使用默认URL"
    i=1
    while [ $i -le 12 ]; do
        eval "template_info=\$url_template_$i"
        template=$(echo "$template_info" | cut -d'|' -f1)
        param1_type=$(echo "$template_info" | cut -d'|' -f2)
        param2_type=$(echo "$template_info" | cut -d'|' -f3)
        param3_type=$(echo "$template_info" | cut -d'|' -f4)
        
        # 使用当天日期生成默认URL
        date_full_default="${currentyear}${currentmonth_padded}${currentday_padded}"
        
        # 根据模板参数数量和类型生成默认URL
        url=""
        case $i in
            1)
                # 模板1: https://a.nodeshare.xyz/uploads/%s/%s/%s.yaml|year|month_no_zero|date_full
                url=$(printf "$template" "$currentyear" "$currentmonth" "$date_full_default")
                echo "生成模板1的默认URL: $url" >&2
                ;;
            2)
                # 模板2: https://nodefree.githubrowcontent.com/%s/%s/%s.yaml|year|month_padded|date_full
                url=$(printf "$template" "$currentyear" "$currentmonth_padded" "$date_full_default")
                echo "生成模板2的默认URL: $url" >&2
                ;;
            3)
                # 模板3: https://free.datiya.com/uploads/%s-clash.yaml|date_full
                url=$(printf "$template" "$date_full_default")
                echo "生成模板3的默认URL: $url" >&2
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
        
        # 保存URL
        if [ -n "$url" ]; then
            eval "template_valid_urls_${i}=\"$url\""
        fi
        
        i=$((i + 1))
    done
else
    # 显示最终使用的URL，并收集到valid_urls变量中
    i=1
    while [ $i -le 12 ]; do
        eval "url_value=\$template_valid_urls_${i}"
        if [ -n "$url_value" ]; then
            echo "使用模板[$i]: $url_value"
            # 同时收集到valid_urls变量中
            if [ -z "$valid_urls" ]; then
                valid_urls="$url_value"
            else
                valid_urls="$valid_urls|$url_value"
            fi
        fi
        i=$((i + 1))
    done
fi

# 如果没有找到有效的URL，则使用默认URL
if [ -z "$valid_urls" ]; then
    echo "未找到任何有效URL，使用默认URL"
    i=1
    while [ $i -le 12 ]; do
        eval "template_info=\$url_template_$i"
        template=$(echo "$template_info" | cut -d'|' -f1)
        param1_type=$(echo "$template_info" | cut -d'|' -f2)
        param2_type=$(echo "$template_info" | cut -d'|' -f3)
        param3_type=$(echo "$template_info" | cut -d'|' -f4)
            
        # 使用当天日期生成默认URL
        date_full_default="${currentyear}${currentmonth_padded}${currentday_padded}"
            
        # 根据模板参数数量和类型生成默认URL
        url=""
        case $i in
            1)
                # 模板1: https://a.nodeshare.xyz/uploads/%s/%s/%s.yaml|year|month_no_zero|date_full
                url=$(printf "$template" "$currentyear" "$currentmonth" "$date_full_default")
                echo "生成模板1的备用URL: $url" >&2
                ;;
            2)
                # 模板2: https://nodefree.githubrowcontent.com/%s/%s/%s.yaml|year|month_padded|date_full
                url=$(printf "$template" "$currentyear" "$currentmonth_padded" "$date_full_default")
                echo "生成模板2的备用URL: $url" >&2
                ;;
            3)
                # 模板3: https://free.datiya.com/uploads/%s-clash.yaml|date_full
                url=$(printf "$template" "$date_full_default")
                echo "生成模板3的备用URL: $url" >&2
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
            
        # 保存URL
        if [ -n "$url" ]; then
            eval "template_valid_urls_${i}=\"$url\""
            if [ -z "$valid_urls" ]; then
                valid_urls="$url"
            else
                valid_urls="$valid_urls|$url"
            fi
        fi
            
        i=$((i + 1))
    done
fi

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
i=1
while [ $i -le 12 ]; do
    eval "url_value=\$template_valid_urls_${i}"
    if [ -n "$url_value" ]; then
        echo "  * $url_value"
        valid_url_count=$((valid_url_count + 1))
    fi
    i=$((i + 1))
done

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
if wget --timeout=90 --tries=3 --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" -q "$subscribeclash" -O ./clash.yaml; then
    echo "Clash配置下载成功"
else
    echo "Clash配置下载失败，退出码: $?"
    # 尝试显示更多错误信息
    wget --timeout=90 --tries=1 --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" -S "$subscribeclash" -O ./clash.yaml 2>&1 | head -20
fi

echo "下载V2Ray配置..."
if wget --timeout=90 --tries=3 --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" -q "$subscribeV2ray" -O ./v2ray.txt; then
    echo "V2Ray配置下载成功"
else
    echo "V2Ray配置下载失败，退出码: $?"
    # 尝试显示更多错误信息
    wget --timeout=90 --tries=1 --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" -S "$subscribeV2ray" -O ./v2ray.txt 2>&1 | head -20
fi

echo "========== 清理无效节点并去重 =========="
# 删除clash配置中cipher: "" 和 password: "" 的节点，并按server去重
if [ -f "./clash.yaml" ]; then
    # 创建临时文件
    temp_file=$(mktemp)
    
    # 使用Shell脚本处理YAML文件
    # 标记处理状态
    in_proxy=0
    in_proxy_groups=0
    in_current_proxy=0
    in_proxies_list=0
    in_url_test_group=0
    remove_current=0
    current_server=""
    proxy_content=""
    
    # 用于存储已见过的server和节点名称
    servers_seen=""
    valid_names=""
    deleted_names=""
    
    # 初始化所有状态变量
    in_proxy=0
    in_proxy_groups=0
    in_current_proxy=0
    in_proxies_list=0
    in_url_test_group=0
    remove_current=0
    current_server=""
    proxy_content=""
    
    # 添加调试信息
    echo "开始处理clash.yaml文件..." >&2
    
    while IFS= read -r line; do
        # 检查是否是proxies部分开始
        if echo "$line" | grep -q "^proxies:$"; then
            in_proxy=1
            in_proxy_groups=0
            in_proxies_list=0
            in_url_test_group=0
            echo "$line"
            echo "进入proxies部分" >&2
            continue
        fi
        
        # 检查是否是proxy-groups部分开始
        if echo "$line" | grep -q "^proxy-groups:$"; then
            in_proxy=0
            in_proxy_groups=1
            in_proxies_list=0
            in_url_test_group=0
            echo "$line"
            echo "进入proxy-groups部分" >&2
            # 输出删除的节点名称用于调试
            echo "删除的节点名称: $deleted_names" >&2
            continue
        fi
        
        # 处理proxies部分
        if [ $in_proxy -eq 1 ]; then
            # 检查是否是新节点开始
            if echo "$line" | grep -q "^  - "; then
                # 处理上一个节点（如果存在）
                if [ $in_current_proxy -eq 1 ]; then
                    if [ $remove_current -eq 0 ]; then
                        # 检查是否已存在相同server的节点
                        is_duplicate=0
                        if [ -n "$current_server" ]; then
                            if echo " $servers_seen " | grep -q " $current_server "; then
                                is_duplicate=1
                            fi
                        fi
                        
                        if [ $is_duplicate -eq 0 ]; then
                            # server未出现过，输出节点
                            echo "$proxy_content"
                            # 记录server
                            if [ -n "$current_server" ]; then
                                servers_seen="$servers_seen $current_server"
                            fi
                            # 记录有效的节点名称
                            if echo "$proxy_content" | grep -o "name: [^,}]*" | head -1 | grep -q "name:"; then
                                node_name=$(echo "$proxy_content" | grep -o "name: [^,}]*" | head -1 | cut -d" " -f2-)
                                # 使用引号包围节点名称以处理特殊字符
                                valid_names="$valid_names \"$node_name\""
                                echo "添加有效节点: \"$node_name\"" >&2
                            fi
                        else
                            # 记录被删除的重复节点名称
                            if echo "$proxy_content" | grep -o "name: [^,}]*" | head -1 | grep -q "name:"; then
                                node_name=$(echo "$proxy_content" | grep -o "name: [^,}]*" | head -1 | cut -d" " -f2-)
                                # 使用引号包围节点名称以处理特殊字符
                                deleted_names="$deleted_names \"$node_name\""
                                echo "删除重复节点: \"$node_name\"" >&2
                            fi
                        fi
                    else
                        # 记录被删除的无效节点名称
                        if echo "$proxy_content" | grep -o "name: [^,}]*" | head -1 | grep -q "name:"; then
                            node_name=$(echo "$proxy_content" | grep -o "name: [^,}]*" | head -1 | cut -d" " -f2-)
                            # 使用引号包围节点名称以处理特殊字符
                            deleted_names="$deleted_names \"$node_name\""
                            echo "删除无效节点: \"$node_name\" (cipher或password为空)" >&2
                        fi
                    fi
                fi
                
                # 重置状态以处理新节点
                in_current_proxy=1
                proxy_content="$line"
                current_server=""
                remove_current=0
                
                # 检查是否包含 cipher: "" 或 password: ""
                if echo "$line" | grep -q "cipher: \"\"" || echo "$line" | grep -q "password: \"\""; then
                    remove_current=1
                fi
                
                # 尝试提取server
                if echo "$line" | grep -o "server: [^,}]*" | head -1 | grep -q "server:"; then
                    current_server=$(echo "$line" | grep -o "server: [^,}]*" | head -1 | cut -d" " -f2)
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
                
                # 继续尝试提取server
                if [ -z "$current_server" ]; then
                    if echo "$line" | grep -o "server: [^,}]*" | head -1 | grep -q "server:"; then
                        current_server=$(echo "$line" | grep -o "server: [^,}]*" | head -1 | cut -d" " -f2)
                    fi
                fi
                continue
            fi
            
            # proxies部分结束
            if echo "$line" | grep -q "^[^ ]" && ! echo "$line" | grep -q "^ "; then
                # 处理最后一个节点
                if [ $in_current_proxy -eq 1 ] && [ $remove_current -eq 0 ]; then
                    # 检查是否已存在相同server的节点
                    is_duplicate=0
                    if [ -n "$current_server" ]; then
                        if echo " $servers_seen " | grep -q " $current_server "; then
                            is_duplicate=1
                        fi
                    fi
                    
                    if [ $is_duplicate -eq 0 ]; then
                        # server未出现过，输出节点
                        echo "$proxy_content"
                        # 记录server
                        if [ -n "$current_server" ]; then
                            servers_seen="$servers_seen $current_server"
                        fi
                        # 记录有效的节点名称
                        if echo "$proxy_content" | grep -o "name: [^,}]*" | head -1 | grep -q "name:"; then
                            node_name=$(echo "$proxy_content" | grep -o "name: [^,}]*" | head -1 | cut -d" " -f2-)
                            # 使用引号包围节点名称以处理特殊字符
                            valid_names="$valid_names \"$node_name\""
                            echo "添加有效节点: \"$node_name\"" >&2
                        fi
                    else
                        # 记录被删除的重复节点名称
                        if echo "$proxy_content" | grep -o "name: [^,}]*" | head -1 | grep -q "name:"; then
                            node_name=$(echo "$proxy_content" | grep -o "name: [^,}]*" | head -1 | cut -d" " -f2-)
                            # 使用引号包围节点名称以处理特殊字符
                            deleted_names="$deleted_names \"$node_name\""
                            echo "删除重复节点: \"$node_name\"" >&2
                        fi
                    fi
                elif [ $in_current_proxy -eq 1 ] && [ $remove_current -eq 1 ]; then
                    # 记录被删除的无效节点名称
                    if echo "$proxy_content" | grep -o "name: [^,}]*" | head -1 | grep -q "name:"; then
                        node_name=$(echo "$proxy_content" | grep -o "name: [^,}]*" | head -1 | cut -d" " -f2-)
                        # 使用引号包围节点名称以处理特殊字符
                        deleted_names="$deleted_names \"$node_name\""
                        echo "删除无效节点: \"$node_name\" (cipher或password为空)" >&2
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
                echo "$line"
                echo "发现新的proxy-group" >&2
                continue
            fi
            
            # 检查group类型
            if echo "$line" | grep -q "^    type: url-test"; then
                in_url_test_group=1
                current_group_type="url-test"
                echo "$line"
                echo "当前group类型为url-test" >&2
                continue
            fi
            
            # 检查是否是proxies列表开始
            if echo "$line" | grep -q "^    proxies:$"; then
                in_proxies_list=1
                echo "$line"
                echo "进入proxies列表" >&2
                if [ "$in_url_test_group" = "1" ]; then
                    echo "当前在url-test组中" >&2
                fi
                continue
            fi
            
            # 如果在proxies列表中
            if [ $in_proxies_list -eq 1 ]; then
                # 检查是否是proxies列表条目 (以"      - "开头)
                if echo "$line" | grep -q "^      - "; then
                    # 特殊处理url-test组
                    if [ $in_url_test_group -eq 1 ]; then
                        # 提取proxy名称
                        proxy_name=""
                        if echo "$line" | grep -q "^      - [^{]"; then
                            # 处理普通格式: "      - ProxyName"
                            proxy_name=$(echo "$line" | sed 's/^      - //' | sed 's/ *#.*//' | sed 's/ *$//')
                        elif echo "$line" | grep -q "^      -{name:"; then
                            # 处理内联格式: "      - {name: ProxyName, ...}"
                            proxy_name=$(echo "$line" | grep -o "name: [^,}]*" | head -1 | cut -d" " -f2-)
                        fi
                        
                        # 如果这个proxy名称已在删除列表中或不在有效节点列表中，则跳过不输出
                        if [ -n "$proxy_name" ]; then
                            echo "检查url-test节点引用: \"$proxy_name\"" >&2
                            # 检查是否在有效节点列表中
                            if echo " $valid_names " | grep -q " \"$proxy_name\" "; then
                                echo "保留url-test组中的有效引用: \"$proxy_name\"" >&2
                                echo "$line"
                            else
                                echo "从url-test组中移除无效引用: \"$proxy_name\"" >&2
                                # 不输出该行，相当于移除该引用
                            fi
                            continue
                        fi
                    fi
                    # 对于非url-test组或者无法提取名称的情况，直接输出
                    echo "$line"
                    continue
                else
                    # 不是proxies列表条目，可能是结束或其他属性
                    # 只有在遇到其他属性时才重置proxies列表标记
                    if echo "$line" | grep -q "^    [a-z]" && ! echo "$line" | grep -q "^    proxies:"; then
                        in_proxies_list=0
                        in_url_test_group=0
                        echo "退出proxies列表" >&2
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
fi

echo "========== 任务完成 =========="
