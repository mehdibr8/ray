#!/bin/bash

# ===================================
#        UDP2RAW Manager
# ===================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

BINARY_PATH=$(realpath ./udp2raw_amd64 2>/dev/null || echo "/root/udp2raw_amd64")

# ===================================
#           Main Menu
# ===================================
main_menu() {
    clear
    echo -e "${CYAN}=============================${NC}"
    echo -e "${CYAN}       UDP2RAW Manager       ${NC}"
    echo -e "${CYAN}=============================${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Tunnel     - Install a new tunnel"
    echo -e "  ${YELLOW}2)${NC} Settings   - Edit existing tunnel"
    echo -e "  ${RED}3)${NC} Uninstall  - Remove tunnel(s)"
    echo ""
    read -p "Select (1/2/3): " MAIN_CHOICE
    echo ""

    case $MAIN_CHOICE in
        1) select_tunnel_install ;;
        2) select_tunnel_edit ;;
        3) select_tunnel_uninstall ;;
        *)
            echo -e "${RED}Invalid choice!${NC}"
            sleep 1
            main_menu
            ;;
    esac
}

# ===================================
#       List Installed Tunnels
# ===================================
list_tunnels() {
    echo -e "${CYAN}Installed Tunnels:${NC}"
    local found=0
    for i in $(seq 1 10); do
        if [ -f "/etc/systemd/system/udp2raw-tunnel${i}.service" ]; then
            STATUS=$(systemctl is-active udp2raw-tunnel${i} 2>/dev/null)
            if [ "$STATUS" == "active" ]; then
                STATUS_COLOR="${GREEN}● Active${NC}"
            else
                STATUS_COLOR="${RED}● Inactive${NC}"
            fi
            DESC=$(grep 'Description=' /etc/systemd/system/udp2raw-tunnel${i}.service | cut -d'-' -f3-)
            echo -e "  ${YELLOW}Tunnel ${i}${NC} -${DESC} | $STATUS_COLOR"
            found=1
        fi
    done
    if [ $found -eq 0 ]; then
        echo -e "  ${RED}No tunnels installed.${NC}"
    fi
    echo ""
}

# ===================================
#     Select Tunnel Number (Install)
# ===================================
select_tunnel_install() {
    clear
    echo -e "${CYAN}--- Select Tunnel Number to Install ---${NC}"
    echo ""
    list_tunnels
    echo -e "${YELLOW}Choose tunnel slot (1 to 10):${NC}"
    for i in $(seq 1 10); do
        if [ -f "/etc/systemd/system/udp2raw-tunnel${i}.service" ]; then
            echo -e "  ${RED}Tunnel ${i}${NC} - Installed"
        else
            echo -e "  ${GREEN}Tunnel ${i}${NC} - Empty"
        fi
    done
    echo ""
    read -p "Tunnel number: " TUNNEL_NUM

    if ! [[ "$TUNNEL_NUM" =~ ^[1-9]$|^10$ ]]; then
        echo -e "${RED}Invalid number! Must be between 1 and 10.${NC}"
        sleep 2
        main_menu
        return
    fi

    install_tunnel $TUNNEL_NUM
}

# ===================================
#     Select Tunnel Number (Edit)
# ===================================
select_tunnel_edit() {
    clear
    echo -e "${CYAN}--- Select Tunnel to Edit ---${NC}"
    echo ""
    list_tunnels

    local found=0
    for i in $(seq 1 10); do
        [ -f "/etc/systemd/system/udp2raw-tunnel${i}.service" ] && found=1
    done

    if [ $found -eq 0 ]; then
        echo -e "${RED}No tunnels available to edit!${NC}"
        sleep 2
        main_menu
        return
    fi

    read -p "Tunnel number to edit: " TUNNEL_NUM

    if ! [ -f "/etc/systemd/system/udp2raw-tunnel${TUNNEL_NUM}.service" ]; then
        echo -e "${RED}Tunnel ${TUNNEL_NUM} is not installed!${NC}"
        sleep 2
        main_menu
        return
    fi

    edit_tunnel $TUNNEL_NUM
}

# ===================================
#     Select Tunnel Number (Remove)
# ===================================
select_tunnel_uninstall() {
    clear
    echo -e "${CYAN}--- Select Tunnel to Remove ---${NC}"
    echo ""
    list_tunnels

    local found=0
    for i in $(seq 1 10); do
        [ -f "/etc/systemd/system/udp2raw-tunnel${i}.service" ] && found=1
    done

    if [ $found -eq 0 ]; then
        echo -e "${RED}No tunnels available to remove!${NC}"
        sleep 2
        main_menu
        return
    fi

    echo -e "  ${RED}0)${NC} Remove ALL tunnels"
    echo ""
    read -p "Tunnel number to remove (or 0 for all): " TUNNEL_NUM

    if [ "$TUNNEL_NUM" == "0" ]; then
        uninstall_all_tunnels
    elif ! [ -f "/etc/systemd/system/udp2raw-tunnel${TUNNEL_NUM}.service" ]; then
        echo -e "${RED}Tunnel ${TUNNEL_NUM} is not installed!${NC}"
        sleep 2
        main_menu
    else
        uninstall_tunnel $TUNNEL_NUM
    fi
}

# ===================================
#         Select Protocol
# ===================================
select_protocol() {
    echo -e "${YELLOW}Select protocol:${NC}"
    echo "  1) faketcp"
    echo "  2) udp"
    echo "  3) icmp"
    read -p "Choice (1/2/3): " PROTO_CHOICE

    case $PROTO_CHOICE in
        1) PROTOCOL="faketcp" ;;
        2) PROTOCOL="udp" ;;
        3) PROTOCOL="icmp" ;;
        *)
            echo -e "${RED}Invalid choice!${NC}"
            exit 1
            ;;
    esac
}

# ===================================
#       Create systemd Service
# ===================================
create_service() {
    local TUNNEL_NUM="$1"
    local EXEC_CMD="$2"
    local DESC="$3"
    local SERVICE_FILE="/etc/systemd/system/udp2raw-tunnel${TUNNEL_NUM}.service"

    cat > $SERVICE_FILE << EOF
[Unit]
Description=udp2raw - Tunnel ${TUNNEL_NUM} - ${DESC}
After=network.target

[Service]
Type=simple
ExecStart=${EXEC_CMD}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable udp2raw-tunnel${TUNNEL_NUM}.service
    systemctl restart udp2raw-tunnel${TUNNEL_NUM}.service

    echo ""
    echo -e "${GREEN}[OK] Tunnel ${TUNNEL_NUM} started successfully!${NC}"
    echo ""
    echo -e "${CYAN}Useful commands:${NC}"
    echo "  Status  : systemctl status udp2raw-tunnel${TUNNEL_NUM}"
    echo "  Logs    : journalctl -u udp2raw-tunnel${TUNNEL_NUM} -f"
    echo "  Stop    : systemctl stop udp2raw-tunnel${TUNNEL_NUM}"
    echo "  Restart : systemctl restart udp2raw-tunnel${TUNNEL_NUM}"
}

# ===================================
#        1) Install Tunnel
# ===================================
install_tunnel() {
    local TUNNEL_NUM="$1"
    echo ""
    echo -e "${CYAN}--- Install Tunnel ${TUNNEL_NUM} ---${NC}"
    echo ""
    echo -e "${YELLOW}Select server type:${NC}"
    echo "  1) Foreign Server (Server mode)"
    echo "  2) Iran Server (Client mode)"
    echo ""
    read -p "Choice (1/2): " SERVER_TYPE
    echo ""

    if [ "$SERVER_TYPE" == "1" ]; then
        echo -e "${GREEN}--- Foreign Server Settings ---${NC}"
        echo ""
        read -p "Listen port (e.g. 1373): " LISTEN_PORT
        read -p "Password: " PASSWORD
        echo ""
        select_protocol

        EXEC_CMD="${BINARY_PATH} -s -l 0.0.0.0:${LISTEN_PORT} -r 127.0.0.1:1010 -k \"${PASSWORD}\" --raw-mode ${PROTOCOL} --seq-mode 1 --disable-color --fix-gro"
        create_service "$TUNNEL_NUM" "$EXEC_CMD" "Server port ${LISTEN_PORT}"

    elif [ "$SERVER_TYPE" == "2" ]; then
        echo -e "${GREEN}--- Iran Server Settings ---${NC}"
        echo ""
        read -p "Local listen port (e.g. 3336): " LOCAL_PORT
        read -p "Foreign server IP: " REMOTE_IP
        read -p "Foreign server port (e.g. 1373): " REMOTE_PORT
        read -p "Password: " PASSWORD
        echo ""
        select_protocol

        EXEC_CMD="${BINARY_PATH} -c -l 0.0.0.0:${LOCAL_PORT} -r ${REMOTE_IP}:${REMOTE_PORT} -k \"${PASSWORD}\" --raw-mode ${PROTOCOL} --disable-color --fix-gro"
        create_service "$TUNNEL_NUM" "$EXEC_CMD" "Client ${REMOTE_IP}:${REMOTE_PORT}"

    else
        echo -e "${RED}Invalid choice!${NC}"
        exit 1
    fi
}

# ===================================
#        2) Edit Tunnel
# ===================================
edit_tunnel() {
    local TUNNEL_NUM="$1"
    local SERVICE_FILE="/etc/systemd/system/udp2raw-tunnel${TUNNEL_NUM}.service"

    echo ""
    echo -e "${CYAN}--- Edit Tunnel ${TUNNEL_NUM} ---${NC}"
    echo ""

    CURRENT_CMD=$(grep "ExecStart=" $SERVICE_FILE | sed 's/ExecStart=//')
    echo -e "${YELLOW}Current config:${NC}"
    echo -e "${BLUE}$CURRENT_CMD${NC}"
    echo ""

    if echo "$CURRENT_CMD" | grep -q " -s "; then
        SERVER_TYPE="1"
        echo -e "${GREEN}Type: Foreign Server${NC}"
    else
        SERVER_TYPE="2"
        echo -e "${GREEN}Type: Iran Client${NC}"
    fi

    echo ""
    echo -e "${YELLOW}What do you want to edit?${NC}"

    if [ "$SERVER_TYPE" == "1" ]; then
        CUR_PORT=$(echo "$CURRENT_CMD" | grep -oP '(?<=-l 0.0.0.0:)\d+')
        CUR_PASS=$(echo "$CURRENT_CMD" | grep -oP '(?<=-k ")[^"]+')
        CUR_PROTO=$(echo "$CURRENT_CMD" | grep -oP '(?<=--raw-mode )\S+')

        echo "  1) Listen port   [current: $CUR_PORT]"
        echo "  2) Password      [current: $CUR_PASS]"
        echo "  3) Protocol      [current: $CUR_PROTO]"
        echo "  4) All"
        read -p "Choice: " EDIT_CHOICE

        case $EDIT_CHOICE in
            1)
                read -p "New port [current: $CUR_PORT]: " NEW_PORT
                LISTEN_PORT=${NEW_PORT:-$CUR_PORT}; PASSWORD="$CUR_PASS"; PROTOCOL="$CUR_PROTO"
                ;;
            2)
                read -p "New password: " NEW_PASS
                LISTEN_PORT="$CUR_PORT"; PASSWORD=${NEW_PASS:-$CUR_PASS}; PROTOCOL="$CUR_PROTO"
                ;;
            3)
                LISTEN_PORT="$CUR_PORT"; PASSWORD="$CUR_PASS"; select_protocol
                ;;
            4)
                read -p "Port [current: $CUR_PORT]: " NEW_PORT
                LISTEN_PORT=${NEW_PORT:-$CUR_PORT}
                read -p "Password [current: $CUR_PASS]: " NEW_PASS
                PASSWORD=${NEW_PASS:-$CUR_PASS}
                select_protocol
                ;;
            *) echo -e "${RED}Invalid choice!${NC}"; exit 1 ;;
        esac

        EXEC_CMD="${BINARY_PATH} -s -l 0.0.0.0:${LISTEN_PORT} -r 127.0.0.1:1010 -k \"${PASSWORD}\" --raw-mode ${PROTOCOL} --seq-mode 1 --disable-color --fix-gro"
        create_service "$TUNNEL_NUM" "$EXEC_CMD" "Server port ${LISTEN_PORT}"

    else
        CUR_LOCAL_PORT=$(echo "$CURRENT_CMD" | grep -oP '(?<=-l 0.0.0.0:)\d+')
        CUR_REMOTE_IP=$(echo "$CURRENT_CMD" | grep -oP '(?<=-r )[0-9.]+')
        CUR_REMOTE_PORT=$(echo "$CURRENT_CMD" | grep -oP '(?<=-r [0-9.]{7,15}:)\d+')
        CUR_PASS=$(echo "$CURRENT_CMD" | grep -oP '(?<=-k ")[^"]+')
        CUR_PROTO=$(echo "$CURRENT_CMD" | grep -oP '(?<=--raw-mode )\S+')

        echo "  1) Local port        [current: $CUR_LOCAL_PORT]"
        echo "  2) Foreign server IP [current: $CUR_REMOTE_IP]"
        echo "  3) Foreign port      [current: $CUR_REMOTE_PORT]"
        echo "  4) Password          [current: $CUR_PASS]"
        echo "  5) Protocol          [current: $CUR_PROTO]"
        echo "  6) All"
        read -p "Choice: " EDIT_CHOICE

        case $EDIT_CHOICE in
            1)
                read -p "New local port [current: $CUR_LOCAL_PORT]: " NEW_PORT
                LOCAL_PORT=${NEW_PORT:-$CUR_LOCAL_PORT}
                REMOTE_IP="$CUR_REMOTE_IP"; REMOTE_PORT="$CUR_REMOTE_PORT"; PASSWORD="$CUR_PASS"; PROTOCOL="$CUR_PROTO"
                ;;
            2)
                read -p "New foreign IP [current: $CUR_REMOTE_IP]: " NEW_IP
                REMOTE_IP=${NEW_IP:-$CUR_REMOTE_IP}
                LOCAL_PORT="$CUR_LOCAL_PORT"; REMOTE_PORT="$CUR_REMOTE_PORT"; PASSWORD="$CUR_PASS"; PROTOCOL="$CUR_PROTO"
                ;;
            3)
                read -p "New foreign port [current: $CUR_REMOTE_PORT]: " NEW_RPORT
                REMOTE_PORT=${NEW_RPORT:-$CUR_REMOTE_PORT}
                LOCAL_PORT="$CUR_LOCAL_PORT"; REMOTE_IP="$CUR_REMOTE_IP"; PASSWORD="$CUR_PASS"; PROTOCOL="$CUR_PROTO"
                ;;
            4)
                read -p "New password: " NEW_PASS
                PASSWORD=${NEW_PASS:-$CUR_PASS}
                LOCAL_PORT="$CUR_LOCAL_PORT"; REMOTE_IP="$CUR_REMOTE_IP"; REMOTE_PORT="$CUR_REMOTE_PORT"; PROTOCOL="$CUR_PROTO"
                ;;
            5)
                LOCAL_PORT="$CUR_LOCAL_PORT"; REMOTE_IP="$CUR_REMOTE_IP"; REMOTE_PORT="$CUR_REMOTE_PORT"; PASSWORD="$CUR_PASS"
                select_protocol
                ;;
            6)
                read -p "Local port [current: $CUR_LOCAL_PORT]: " NEW_PORT
                LOCAL_PORT=${NEW_PORT:-$CUR_LOCAL_PORT}
                read -p "Foreign IP [current: $CUR_REMOTE_IP]: " NEW_IP
                REMOTE_IP=${NEW_IP:-$CUR_REMOTE_IP}
                read -p "Foreign port [current: $CUR_REMOTE_PORT]: " NEW_RPORT
                REMOTE_PORT=${NEW_RPORT:-$CUR_REMOTE_PORT}
                read -p "Password [current: $CUR_PASS]: " NEW_PASS
                PASSWORD=${NEW_PASS:-$CUR_PASS}
                select_protocol
                ;;
            *) echo -e "${RED}Invalid choice!${NC}"; exit 1 ;;
        esac

        EXEC_CMD="${BINARY_PATH} -c -l 0.0.0.0:${LOCAL_PORT} -r ${REMOTE_IP}:${REMOTE_PORT} -k \"${PASSWORD}\" --raw-mode ${PROTOCOL} --disable-color --fix-gro"
        create_service "$TUNNEL_NUM" "$EXEC_CMD" "Client ${REMOTE_IP}:${REMOTE_PORT}"
    fi
}

# ===================================
#       3) Uninstall One Tunnel
# ===================================
uninstall_tunnel() {
    local TUNNEL_NUM="$1"
    local SERVICE_FILE="/etc/systemd/system/udp2raw-tunnel${TUNNEL_NUM}.service"

    echo ""
    read -p "Are you sure you want to remove Tunnel ${TUNNEL_NUM}? (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo -e "${YELLOW}Cancelled.${NC}"
        sleep 1
        main_menu
        return
    fi

    systemctl stop udp2raw-tunnel${TUNNEL_NUM}.service
    systemctl disable udp2raw-tunnel${TUNNEL_NUM}.service
    rm -f $SERVICE_FILE
    systemctl daemon-reload

    echo ""
    echo -e "${GREEN}[OK] Tunnel ${TUNNEL_NUM} removed successfully!${NC}"
}

# ===================================
#       Uninstall All Tunnels
# ===================================
uninstall_all_tunnels() {
    echo ""
    read -p "Are you sure you want to remove ALL tunnels? (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo -e "${YELLOW}Cancelled.${NC}"
        sleep 1
        main_menu
        return
    fi

    for i in $(seq 1 10); do
        if [ -f "/etc/systemd/system/udp2raw-tunnel${i}.service" ]; then
            systemctl stop udp2raw-tunnel${i}.service
            systemctl disable udp2raw-tunnel${i}.service
            rm -f /etc/systemd/system/udp2raw-tunnel${i}.service
            echo -e "${GREEN}[OK] Tunnel ${i} removed${NC}"
        fi
    done

    systemctl daemon-reload
    echo ""
    echo -e "${GREEN}[OK] All tunnels removed!${NC}"
}

# ===================================
#            Run Script
# ===================================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root: sudo ./udp2raw_setup.sh${NC}"
    exit 1
fi

main_menu
