#!/bin/bash
# ping_monitor.sh
# Single script: on startup asks whether you are running the "Iran" side or the "Abroad" side
# Iran side: only needs ping (report is sent with pure bash, no curl)
# Abroad side: needs nc (to listen) and curl (to send to Telegram)

# ================= CONFIG =================

# ---- Iran side settings ----
# SERVER_URL has no default — it's asked interactively when you run the Iran side
INTERVAL=60      # time between each report (seconds)
PING_COUNT=10    # number of pings per IP
PING_TIMEOUT=2   # timeout per ping (seconds)

# ---- Abroad side settings ----
# BOT_TOKEN, CHAT_ID, and PORT have no default — asked interactively when you run the Abroad side

# ============================================


# ======================================================================
# Iran side functions
# ======================================================================

run_iran() {
    local SRV_HOST SRV_PORT SRV_PATH SERVER_URL

    SRV_PATH="/report"

    read -p "Enter the abroad server IP: " SRV_HOST
    while [ -z "$SRV_HOST" ]; do
        read -p "Server IP cannot be empty: " SRV_HOST
    done

    read -p "Enter the abroad server port: " SRV_PORT
    while ! [[ "$SRV_PORT" =~ ^[0-9]+$ ]] || [ "$SRV_PORT" -le 0 ] || [ "$SRV_PORT" -gt 65535 ]; do
        read -p "Please enter a valid port number (1-65535): " SRV_PORT
    done

    SERVER_URL="http://${SRV_HOST}:${SRV_PORT}${SRV_PATH}"

    read -p "How many IPs do you want to add? " COUNT
    while ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -le 0 ]; do
        read -p "Please enter a whole number greater than 0: " COUNT
    done

    local IPS=()
    for ((i = 1; i <= COUNT; i++)); do
        read -p "IP #$i: " ip
        while [ -z "$ip" ]; do
            read -p "IP #$i (cannot be empty): " ip
        done
        IPS+=("$ip")
    done

    get_ping_stats() {
        local ip="$1"
        local output avg loss
        output=$(ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$ip" 2>/dev/null)
        avg=$(echo "$output" | tail -1 | awk -F'/' '{print $5}')
        loss=$(echo "$output" | grep -oP '\d+(?=% packet loss)')
        [ -z "$avg" ] && avg="null"
        [ -z "$loss" ] && loss="100"
        echo "${ip}|${avg}|${loss}"
    }

    send_report() {
        local body="$1"
        local content_length=${#body}

        exec 3<>"/dev/tcp/${SRV_HOST}/${SRV_PORT}" || {
            echo "Could not connect to server."
            return 1
        }

        {
            printf 'POST %s HTTP/1.1\r\n' "$SRV_PATH"
            printf 'Host: %s\r\n' "$SRV_HOST"
            printf 'Content-Type: text/plain\r\n'
            printf 'Content-Length: %d\r\n' "$content_length"
            printf 'Connection: close\r\n'
            printf '\r\n'
            printf '%s' "$body"
        } >&3

        timeout 5 cat <&3 >/dev/null
        exec 3<&- 3>&-
    }

    echo "[IRAN] Starting monitoring. Sending reports to: $SERVER_URL"
    echo "IPs: ${IPS[*]}"
    echo

    while true; do
        local BODY=""
        for ip in "${IPS[@]}"; do
            line=$(get_ping_stats "$ip")
            BODY="${BODY}${line}"$'\n'
        done

        if send_report "$BODY"; then
            echo "Report sent:"
        else
            echo "Report failed to send:"
        fi
        printf '%s' "$BODY"
        echo "-----"

        sleep "$INTERVAL"
    done
}


# ======================================================================
# Abroad side functions
# ======================================================================

run_kharej() {
    local PORT

    read -p "Enter your Telegram bot token: " BOT_TOKEN
    while [ -z "$BOT_TOKEN" ]; do
        read -p "Bot token cannot be empty: " BOT_TOKEN
    done

    read -p "Enter your Telegram chat ID: " CHAT_ID
    while [ -z "$CHAT_ID" ]; do
        read -p "Chat ID cannot be empty: " CHAT_ID
    done

    read -p "Enter the port to listen on: " PORT
    while ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -le 0 ] || [ "$PORT" -gt 65535 ]; do
        read -p "Please enter a valid port number (1-65535): " PORT
    done

    send_telegram() {
        local msg="$1"
        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=${CHAT_ID}" \
            --data-urlencode "text=${msg}" >/dev/null
    }

    listen_once() {
        if nc -h 2>&1 | grep -q -- "-p "; then
            nc -l -p "$PORT" 2>/dev/null
        else
            nc -l "$PORT" 2>/dev/null
        fi
    }

    echo "[ABROAD] Server listening on port $PORT ..."

    while true; do
        local REQUEST BODY
        REQUEST=$(listen_once)
        BODY=$(printf '%s\n' "$REQUEST" | awk 'blank{print} /^\r?$/{blank=1}')

        if [ -n "$BODY" ]; then
            local MSG="📡 Ping Report:"
            while IFS='|' read -r ip avg loss; do
                [ -z "$ip" ] && continue
                MSG="${MSG}
${ip} → Avg: ${avg}, Loss: ${loss}%"
            done <<<"$BODY"

            send_telegram "$MSG"
            echo "Report relayed to Telegram."
        fi
    done
}


# ======================================================================
# Selection menu
# ======================================================================

echo "Which side do you want to run?"
echo "  1) Iran    (pings targets and sends reports)"
echo "  2) Abroad  (receives reports and relays them to Telegram)"
read -p "Enter your choice (1 or 2): " CHOICE

case "$CHOICE" in
    1)
        run_iran
        ;;
    2)
        run_kharej
        ;;
    *)
        echo "Invalid choice. Only 1 or 2 is allowed."
        exit 1
        ;;
esac
