#!/usr/bin/env bash

#############################################
# AWS EC2 SSH Interactive Login Script v2.2
# Purpose: Quick select and connect to AWS EC2 instances
# Features: Command-line arguments, Smart IP selection, SSH multiplexing
#############################################

# Check Bash version (requires 4.0+ for associative arrays)
if ((BASH_VERSINFO[0] < 4)); then
    echo "❌ Error: This script requires Bash 4.0 or higher (current: $BASH_VERSION)"
    echo ""
    echo "Solutions:"
    echo "  macOS: brew install bash"
    echo "  Linux: Usually pre-installed, or use: apt-get install bash / yum install bash"
    echo ""
    echo "Then run with explicit path or update your PATH:"
    echo "  /usr/local/bin/bash $0"
    exit 1
fi

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# AWS Configuration
AWS_PROFILES=("prod-ops-sentinel")  # AWS profiles to query
AWS_REGION="ap-east-1"
SSH_KEY_DIR="$HOME/.ssh"
DEFAULT_SSH_KEY="$SSH_KEY_DIR/dev.pem"
DEFAULT_USER="ec2-user"
HISTORY_FILE="$SSH_KEY_DIR/.ec2-history"

# Quick mode flags
QUICK_MODE=false
FORCE_PRIVATE_IP=false
SEARCH_TERM=""
SHOW_HISTORY=false
AUTO_CONNECT_INDEX=""

# ============================================
# Key name mapping configuration
# AWS KeyName -> Actual key file name
# ============================================
declare -A KEY_NAME_MAP=(
    ["devops"]="lumia-devops.pem"
    ["dev"]="lumia-dev.pem"
    ["447055468363"]="447055468363.pem"
    ["ide"]="ide.pem"
    ["hk-devops"]="hk-devops.pem"
    ["ocms-keys"]="ocms-keys.pem"
)

# ============================================
# SSH port mapping configuration
# Instance name pattern -> Custom SSH port
# Instances running services on port 22 (e.g., Docker-mapped GitLab)
# require the host SSH to run on a different port
# ============================================
declare -A SSH_PORT_MAP=(
    ["gemini-gitlab"]="50022"
)

# ============================================
# Instance-specific SSH key override
# When AWS KeyName metadata doesn't match the
# actual authorized_keys on the server
# Instance name -> Override key file name
# ============================================
declare -A INSTANCE_KEY_OVERRIDE=(
    ["gemini-jenkins-slave-01"]="hk-dev.pem"
)

# ============================================
# Smart SSH port lookup function
# ============================================
get_ssh_port_for_instance() {
    local instance_name="$1"

    # Check exact name match in port map
    if [ -n "${SSH_PORT_MAP[$instance_name]}" ]; then
        echo "${SSH_PORT_MAP[$instance_name]}"
        return
    fi

    # Default SSH port
    echo "22"
}

# ============================================
# Username mapping configuration
# Instance name pattern -> SSH username
# Uses contains-match so "gemini-gitlab" matches *gitlab*
# ============================================
get_ssh_user_for_instance() {
    local instance_name="$1"

    # Ubuntu instances (use ubuntu user)
    # Use *pattern* for contains-match (not just prefix-match)
    case "$instance_name" in
        *[Jj]enkins[Mm]aster*|*jenkins-master*)
            echo "ubuntu"
            return
            ;;
        *[Gg]itlab*)
            echo "ec2-user"
            return
            ;;
        *[Oo]pen[Vv][Pp][Nn]*)
            echo "ubuntu"
            return
            ;;
    esac

    # Default to ec2-user (Amazon Linux)
    echo "ec2-user"
}

# ============================================
# Smart SSH key lookup function
# ============================================
find_ssh_key() {
    local key_name="$1"
    local instance_name="$2"

    # Check instance-specific key override first
    # (for cases where AWS KeyName doesn't match actual authorized_keys)
    if [ -n "${INSTANCE_KEY_OVERRIDE[$instance_name]}" ]; then
        local override_key="$SSH_KEY_DIR/${INSTANCE_KEY_OVERRIDE[$instance_name]}"
        if [ -f "$override_key" ]; then
            echo "$override_key"
            return
        fi
    fi

    # If KeyName is empty or N/A, return default key
    if [ "$key_name" == "N/A" ] || [ -z "$key_name" ]; then
        echo "$DEFAULT_SSH_KEY"
        return
    fi

    # Check if there's a mapped key
    if [ -n "${KEY_NAME_MAP[$key_name]}" ]; then
        local mapped_key="$SSH_KEY_DIR/${KEY_NAME_MAP[$key_name]}"
        if [ -f "$mapped_key" ]; then
            echo "$mapped_key"
            return
        fi
    fi

    # Try direct KeyName match
    if [ -f "$SSH_KEY_DIR/${key_name}.pem" ]; then
        echo "$SSH_KEY_DIR/${key_name}.pem"
        return
    fi

    if [ -f "$SSH_KEY_DIR/${key_name}" ]; then
        echo "$SSH_KEY_DIR/${key_name}"
        return
    fi

    # Fallback to default key
    echo "$DEFAULT_SSH_KEY"
}

# ============================================
# Save connection history
# ============================================
save_history() {
    local instance_name="$1"
    local instance_id="$2"
    local timestamp=$(date +%s)
    echo "$timestamp|$instance_name|$instance_id" >> "$HISTORY_FILE"
    # Keep only last 10 records
    tail -10 "$HISTORY_FILE" > "$HISTORY_FILE.tmp" && mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
}

# ============================================
# Show connection history
# ============================================
show_history() {
    if [ ! -f "$HISTORY_FILE" ]; then
        echo -e "${YELLOW}No connection history yet${NC}"
        return
    fi

    echo -e "${BOLD}${CYAN}Recent connections:${NC}\n"
    local count=0
    while IFS='|' read -r timestamp name id; do
        ((count++))
        local date_str=$(date -r "$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Unknown")
        echo -e "${CYAN}$count${NC}. $name ($id) - $date_str"
    done < <(tac "$HISTORY_FILE")
    echo ""
}

# ============================================
# Usage information
# ============================================
show_usage() {
    echo -e "${BOLD}${CYAN}Usage:${NC}"
    echo -e "  ${GREEN}ec2${NC}              - Interactive menu (default)"
    echo -e "  ${GREEN}ec2 <number>${NC}     - Quick connect to instance by number (e.g., ec2 1)"
    echo -e "  ${GREEN}ec2 <name>${NC}       - Search and connect to instance (e.g., ec2 jenkins)"
    echo -e "  ${GREEN}ec2 -l${NC}           - Show recent connection history"
    echo -e "  ${GREEN}ec2 -p <number>${NC}  - Connect using private IP"
    echo -e "  ${GREEN}ec2 -h${NC}           - Show this help"
    echo ""
}

# ============================================
# Parse command-line arguments
# ============================================
parse_arguments() {
    if [ $# -eq 0 ]; then
        return
    fi

    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -l|--history)
            SHOW_HISTORY=true
            ;;
        -p|--private)
            FORCE_PRIVATE_IP=true
            if [ -n "$2" ]; then
                if [[ "$2" =~ ^[0-9]+$ ]]; then
                    AUTO_CONNECT_INDEX="$2"
                    QUICK_MODE=true
                else
                    SEARCH_TERM="$2"
                    QUICK_MODE=true
                fi
            fi
            ;;
        *)
            # If it's a number, quick connect mode
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                AUTO_CONNECT_INDEX="$1"
                QUICK_MODE=true
            else
                # Otherwise treat as search keyword
                SEARCH_TERM="$1"
                QUICK_MODE=true
            fi
            ;;
    esac
}

# ============================================
# Execute SSH connection
# ============================================
do_ssh_connect() {
    local idx="$1"
    local force_public_ip="${2:-false}"

    local selected_id="${instance_ids[$idx]}"
    local selected_name="${instance_names[$idx]}"
    local selected_state="${instance_states[$idx]}"
    local selected_public_ip="${instance_public_ips[$idx]}"
    local selected_private_ip="${instance_private_ips[$idx]}"
    local selected_type="${instance_types[$idx]}"
    local selected_key_name="${instance_key_names[$idx]}"
    local selected_platform="${instance_platforms[$idx]}"
    local selected_profile="${instance_profiles[$idx]}"

    # Check instance state
    if [ "$selected_state" != "running" ]; then
        echo -e "${RED}Error: Instance $selected_name is currently $selected_state, cannot connect${NC}"
        if [ "$QUICK_MODE" = false ]; then
            echo -n -e "${YELLOW}Do you want to start this instance? (y/n): ${NC}"
            read -r start_choice
            if [ "$start_choice" == "y" ] || [ "$start_choice" == "Y" ]; then
                echo -e "${BLUE}Starting instance $selected_name (using profile: $selected_profile)...${NC}"
                AWS_PROFILE=$selected_profile aws ec2 start-instances --region $AWS_REGION --instance-ids "$selected_id"
                echo -e "${GREEN}Instance start command sent, please wait for instance to start and reconnect${NC}"
            fi
        fi
        return 1
    fi

    # Quick mode: show instance info
    if [ "$QUICK_MODE" = true ]; then
        echo ""
        echo -e "${BOLD}${CYAN}Connecting to: $selected_name ($selected_id)${NC}"
        echo -e "  AWS Profile: ${MAGENTA}$selected_profile${NC}"
        echo -e "  Instance Type: $selected_type"
        echo -e "  Public IP: $selected_public_ip"
        echo -e "  Private IP: $selected_private_ip"
        echo -e "  SSH Key: ${MAGENTA}$selected_key_name${NC}"
        [ "$selected_platform" != "N/A" ] && echo -e "  Platform: $selected_platform"
        echo ""
    fi

    # Smart SSH key lookup
    local ssh_key=$(find_ssh_key "$selected_key_name" "$selected_name")

    # Smart SSH port lookup
    local ssh_port=$(get_ssh_port_for_instance "$selected_name")

    # Validate SSH key
    if [ ! -f "$ssh_key" ]; then
        echo -e "${RED}Error: SSH key not found: $ssh_key${NC}"
        echo -e "${YELLOW}Hint: Check for key file at:${NC}"
        echo -e "  1. $SSH_KEY_DIR/${selected_key_name}.pem"
        echo -e "  2. $SSH_KEY_DIR/lumia-${selected_key_name}.pem"
        echo -e "  3. $DEFAULT_SSH_KEY"
        return 1
    fi

    # Smart SSH username selection
    local ssh_user=$(get_ssh_user_for_instance "$selected_name")

    # Smart IP selection
    local target_ip=""
    local connection_type=""

    if [ "$FORCE_PRIVATE_IP" = true ]; then
        # Force private IP
        target_ip="$selected_private_ip"
        connection_type="Private IP (VPN)"
    elif [ "$selected_public_ip" != "N/A" ]; then
        if [ "$QUICK_MODE" = true ] || [ "$force_public_ip" = true ]; then
            # Quick mode: default to public IP
            target_ip="$selected_public_ip"
            connection_type="Public IP"
        else
            # Interactive mode: ask user
            echo -e "${BOLD}Select connection method:${NC}"
            echo -e "  ${GREEN}1${NC} - Use Public IP ($selected_public_ip) - Direct connection"
            echo -e "  ${BLUE}2${NC} - Use Private IP ($selected_private_ip) - Via VPN"
            echo ""
            echo -n -e "${BOLD}Choose [1/2, press Enter for Public IP]: ${NC}"
            read -r ip_choice

            if [ "$ip_choice" == "2" ]; then
                target_ip="$selected_private_ip"
                connection_type="Private IP (VPN)"
            else
                target_ip="$selected_public_ip"
                connection_type="Public IP"
            fi
        fi
    else
        # Only private IP available
        target_ip="$selected_private_ip"
        connection_type="Private IP (VPN)"
    fi

    # Show connection info
    echo ""
    echo -e "${BOLD}${GREEN}Preparing to connect...${NC}"
    echo -e "  Instance: ${CYAN}$selected_name${NC}"
    echo -e "  IP: ${CYAN}$target_ip${NC} ${YELLOW}($connection_type)${NC}"
    echo -e "  User: ${CYAN}$ssh_user${NC} ${YELLOW}(auto-detected)${NC}"
    echo -e "  Key: ${CYAN}$ssh_key${NC}"
    if [ "$ssh_port" != "22" ]; then
        echo -e "  Port: ${CYAN}$ssh_port${NC} ${YELLOW}(custom)${NC}"
    fi

    # Show key mapping info (if using mapping)
    if [ -n "${INSTANCE_KEY_OVERRIDE[$selected_name]}" ]; then
        echo -e "  ${YELLOW}ℹ Key override: $selected_name → ${INSTANCE_KEY_OVERRIDE[$selected_name]}${NC}"
    elif [ -n "${KEY_NAME_MAP[$selected_key_name]}" ]; then
        echo -e "  ${YELLOW}ℹ Key mapping: $selected_key_name → ${KEY_NAME_MAP[$selected_key_name]}${NC}"
    fi

    echo ""

    # Save connection history
    save_history "$selected_name" "$selected_id"

    # Execute SSH connection (with connection multiplexing)
    if [ "$QUICK_MODE" = false ]; then
        echo -e "${YELLOW}Hint: You'll return to menu after disconnecting${NC}"
        echo ""
        sleep 1
    fi

    echo -e "${BOLD}${GREEN}Connecting...${NC}"
    echo ""

    # SSH options: connection multiplexing + custom port
    ssh -i "$ssh_key" \
        -p "$ssh_port" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ControlMaster=auto \
        -o ControlPath="$SSH_KEY_DIR/sockets/%r@%h:%p" \
        -o ControlPersist=10m \
        "$ssh_user@$target_ip"

    local ssh_exit_code=$?

    # After SSH connection ends
    echo ""
    if [ $ssh_exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ Disconnected from $selected_name${NC}"
    else
        echo -e "${RED}✗ SSH connection failed (exit code: $ssh_exit_code)${NC}"
    fi

    return $ssh_exit_code
}

# ============================================
# Main program starts
# ============================================

# Parse command-line arguments
parse_arguments "$@"

# If showing history mode
if [ "$SHOW_HISTORY" = true ]; then
    show_history
    exit 0
fi

# Create SSH sockets directory (for connection multiplexing)
mkdir -p "$SSH_KEY_DIR/sockets"
chmod 700 "$SSH_KEY_DIR/sockets"

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI not installed${NC}"
    exit 1
fi

# Get EC2 instance list
if [ "$QUICK_MODE" = false ]; then
    clear
    echo -e "${BOLD}${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           AWS EC2 SSH Login Menu v2.2 (Gemini)                ║"
    echo "║           Profile: prod-ops-sentinel                           ║"
    echo "║           Region: ap-east-1 (Hong Kong)                        ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
fi

# Parse instance data and create menu
declare -a instance_ids
declare -a instance_names
declare -a instance_states
declare -a instance_public_ips
declare -a instance_private_ips
declare -a instance_types
declare -a instance_key_names
declare -a instance_platforms
declare -a instance_profiles  # Record which profile each instance belongs to

echo -e "${BLUE}Fetching EC2 instance list...${NC}"

# Get instances from multiple profiles
ALL_INSTANCES=""
for profile in "${AWS_PROFILES[@]}"; do
    echo -e "${BLUE}  - Querying profile: ${CYAN}$profile${NC}"
    PROFILE_INSTANCES=$(AWS_PROFILE=$profile aws ec2 describe-instances \
        --region $AWS_REGION \
        --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name,PublicIpAddress,PrivateIpAddress,InstanceType,KeyName,PlatformDetails]' \
        --output json 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$PROFILE_INSTANCES" ] && [ "$PROFILE_INSTANCES" != "[]" ]; then
        # Add profile tag to each instance (add extra field in JSON)
        # Use jq to add profile info, if jq not available handle manually
        if command -v jq &> /dev/null; then
            PROFILE_INSTANCES=$(echo "$PROFILE_INSTANCES" | jq --arg prof "$profile" '.[][] |= . + [$prof]')
        else
            # Simple handling: add profile name at end of each instance array
            PROFILE_INSTANCES=$(echo "$PROFILE_INSTANCES" | sed "s/\]/,\"$profile\"]/g")
        fi

        if [ -z "$ALL_INSTANCES" ]; then
            ALL_INSTANCES="$PROFILE_INSTANCES"
        else
            # Merge instance lists
            ALL_INSTANCES=$(echo "$ALL_INSTANCES" | sed 's/\]\]$/],/' ; echo "$PROFILE_INSTANCES" | sed 's/^\[\[/[/')
        fi
    else
        echo -e "${YELLOW}    Warning: Cannot get instances from profile $profile or no instances${NC}"
    fi
done

if [ -z "$ALL_INSTANCES" ] || [ "$ALL_INSTANCES" == "[]" ]; then
    echo -e "${RED}Error: Cannot get EC2 instance list from any profile${NC}"
    exit 1
fi

INSTANCES="$ALL_INSTANCES"

index=0
while IFS= read -r line; do
    if [[ $line =~ \"i-[a-z0-9]+\" ]]; then
        instance_id=$(echo "$line" | grep -o 'i-[a-z0-9]*')

        # Read complete instance info (9 lines, including profile)
        read -r name_line
        read -r state_line
        read -r public_ip_line
        read -r private_ip_line
        read -r instance_type_line
        read -r key_name_line
        read -r platform_line
        read -r profile_line

        name=$(echo "$name_line" | sed 's/[",]//g' | xargs)
        state=$(echo "$state_line" | sed 's/[",]//g' | xargs)
        public_ip=$(echo "$public_ip_line" | sed 's/[",]//g' | xargs)
        private_ip=$(echo "$private_ip_line" | sed 's/[",]//g' | xargs)
        instance_type=$(echo "$instance_type_line" | sed 's/[",]//g' | xargs)
        key_name=$(echo "$key_name_line" | sed 's/[",]//g' | xargs)
        platform=$(echo "$platform_line" | sed 's/[",]//g' | xargs)
        profile=$(echo "$profile_line" | sed 's/[",]//g' | xargs)

        # Set to N/A if null
        [[ "$public_ip" == "null" ]] && public_ip="N/A"
        [[ "$private_ip" == "null" ]] && private_ip="N/A"
        [[ "$key_name" == "null" ]] && key_name="N/A"
        [[ "$platform" == "null" ]] && platform="N/A"
        [[ -z "$profile" || "$profile" == "null" ]] && profile="unknown"

        instance_ids[$index]=$instance_id
        instance_names[$index]=$name
        instance_states[$index]=$state
        instance_public_ips[$index]=$public_ip
        instance_private_ips[$index]=$private_ip
        instance_types[$index]=$instance_type
        instance_key_names[$index]=$key_name
        instance_platforms[$index]=$platform
        instance_profiles[$index]=$profile

        ((index++))
    fi
done < <(echo "$INSTANCES" | grep -E '(i-[a-z0-9]+|"[^"]*"|null)')

# Quick mode processing
if [ "$QUICK_MODE" = true ]; then
    # If index specified
    if [ -n "$AUTO_CONNECT_INDEX" ]; then
        idx=$((AUTO_CONNECT_INDEX - 1))
        if [ $idx -ge 0 ] && [ $idx -lt ${#instance_ids[@]} ]; then
            do_ssh_connect "$idx" true
            exit $?
        else
            echo -e "${RED}Error: Invalid instance number $AUTO_CONNECT_INDEX (valid range: 1-${#instance_ids[@]})${NC}"
            exit 1
        fi
    # If search keyword specified
    elif [ -n "$SEARCH_TERM" ]; then
        matched_indices=()
        for i in "${!instance_names[@]}"; do
            # Case-insensitive search
            if [[ "${instance_names[$i],,}" =~ ${SEARCH_TERM,,} ]]; then
                matched_indices+=($i)
            fi
        done

        if [ ${#matched_indices[@]} -eq 0 ]; then
            echo -e "${RED}Error: No instances found containing '$SEARCH_TERM'${NC}"
            exit 1
        elif [ ${#matched_indices[@]} -eq 1 ]; then
            # Only one found, connect directly
            echo -e "${GREEN}Found matching instance: ${instance_names[${matched_indices[0]}]}${NC}"
            do_ssh_connect "${matched_indices[0]}" true
            exit $?
        else
            # Multiple found, show list
            echo -e "${YELLOW}Found ${#matched_indices[@]} matching instances:${NC}\n"
            for i in "${!matched_indices[@]}"; do
                idx=${matched_indices[$i]}
                num=$((i + 1))
                echo -e "${CYAN}$num${NC}. ${instance_names[$idx]} (${instance_states[$idx]}) - ${instance_public_ips[$idx]}"
            done
            echo ""
            echo -n -e "${BOLD}Choose [1-${#matched_indices[@]}]: ${NC}"
            read -r choice

            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#matched_indices[@]} ]; then
                selected_idx=${matched_indices[$((choice - 1))]}
                do_ssh_connect "$selected_idx" true
                exit $?
            else
                echo -e "${RED}Invalid choice${NC}"
                exit 1
            fi
        fi
    fi
fi

# Interactive mode: show instance list
echo ""
echo -e "${BOLD}Available EC2 Instances:${NC}"
echo ""
printf "${BOLD}%-4s %-25s %-13s %-12s %-18s %-15s %-12s %-12s${NC}\n" "No." "Instance Name" "Profile" "State" "Public IP" "Private IP" "Type" "SSH Key"
echo "────────────────────────────────────────────────────────────────────────────────────────────────────────────────────"

for i in "${!instance_ids[@]}"; do
    # Set color based on state
    if [ "${instance_states[$i]}" == "running" ]; then
        state_color="${GREEN}✓ run${NC}"
    elif [ "${instance_states[$i]}" == "stopped" ]; then
        state_color="${RED}✗ stop${NC}"
    else
        state_color="${YELLOW}${instance_states[$i]}${NC}"
    fi

    # Set name color based on environment
    name="${instance_names[$i]}"
    if [[ $name == prd-* ]] || [[ $name == PRD-* ]]; then
        name_color="${RED}${name}${NC}"
    elif [[ $name == dev-* ]] || [[ $name == DEV-* ]]; then
        name_color="${GREEN}${name}${NC}"
    elif [[ $name == stg-* ]] || [[ $name == STG-* ]]; then
        name_color="${YELLOW}${name}${NC}"
    elif [[ $name == rel-* ]] || [[ $name == REL-* ]]; then
        name_color="${BLUE}${name}${NC}"
    elif [[ $name == *-demo-* ]] || [[ $name == demo-* ]]; then
        name_color="${MAGENTA}${name}${NC}"
    else
        name_color="${CYAN}${name}${NC}"
    fi

    # Set key color
    key_name="${instance_key_names[$i]}"
    if [[ $key_name == "N/A" ]]; then
        key_color="${YELLOW}${key_name}${NC}"
    else
        key_color="${MAGENTA}${key_name}${NC}"
    fi

    # Set profile color
    profile="${instance_profiles[$i]}"
    if [[ $profile == "prod-ops-sentinel" ]]; then
        profile_color="${BLUE}sentinel${NC}"
    else
        profile_color="${YELLOW}${profile}${NC}"
    fi

    num=$((i + 1))
    printf "%-4s %-35s %-22s %-20s %-18s %-15s %-12s %-12s\n" \
        "$num" \
        "$(echo -e $name_color)" \
        "$(echo -e $profile_color)" \
        "$(echo -e $state_color)" \
        "${instance_public_ips[$i]}" \
        "${instance_private_ips[$i]}" \
        "${instance_types[$i]}" \
        "$(echo -e $key_color)"
done

echo ""
echo -e "${BOLD}Quick commands:${NC}"
echo -e "  ${CYAN}ec2 <number>${NC}  - Quick connect (e.g., ec2 1)"
echo -e "  ${CYAN}ec2 <name>${NC}    - Search connect (e.g., ec2 jenkins)"
echo -e "  ${CYAN}ec2 -l${NC}        - Show connection history"
echo ""
echo -e "${BOLD}Special options:${NC}"
echo -e "  ${CYAN}r${NC} - Refresh instance list"
echo -e "  ${CYAN}q${NC} - Quit"
echo ""

# Select instance
while true; do
    echo -n -e "${BOLD}Select instance number [1-${#instance_ids[@]}], r=refresh, q=quit: ${NC}"
    read -r choice

    # Handle special options
    if [ "$choice" == "q" ] || [ "$choice" == "Q" ]; then
        echo -e "${YELLOW}Exiting${NC}"
        exit 0
    elif [ "$choice" == "r" ] || [ "$choice" == "R" ]; then
        echo -e "${BLUE}Refreshing list...${NC}"
        exec "$0"
        exit 0
    fi

    # Validate input
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#instance_ids[@]}" ]; then
        echo -e "${RED}Invalid choice, please enter number between 1-${#instance_ids[@]}${NC}"
        continue
    fi

    # Connect to selected instance
    idx=$((choice - 1))
    echo ""
    echo -e "${BOLD}${CYAN}Selected instance: ${instance_names[$idx]} (${instance_ids[$idx]})${NC}"
    echo -e "  AWS Profile: ${MAGENTA}${instance_profiles[$idx]}${NC}"
    echo -e "  Instance Type: ${instance_types[$idx]}"
    echo -e "  Public IP: ${instance_public_ips[$idx]}"
    echo -e "  Private IP: ${instance_private_ips[$idx]}"
    echo -e "  SSH Key: ${MAGENTA}${instance_key_names[$idx]}${NC}"
    if [ "${instance_platforms[$idx]}" != "N/A" ]; then
        echo -e "  Platform: ${instance_platforms[$idx]}"
    fi
    echo ""

    do_ssh_connect "$idx" false

    # Ask if continue after SSH connection ends
    echo ""
    echo -n -e "${BOLD}Connect to another instance? (y/n): ${NC}"
    read -r continue_choice

    if [ "$continue_choice" != "y" ] && [ "$continue_choice" != "Y" ]; then
        echo -e "${CYAN}Thanks for using, goodbye!${NC}"
        exit 0
    fi

    # Refresh menu
    exec "$0"
    exit 0
done
