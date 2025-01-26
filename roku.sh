#!/usr/bin/env bash

# Roku Remote Control Script
# by bess

# Ensure that the script is executable:
# chmod +x roku.sh
# To add the script to your PATH, you can create a symbolic link:
# sudo ln -s /path/to/roku.sh /usr/local/bin/roku

# Roku Remote Control Script - Dependency Check and Auto-Setup Version

# -------------------------
# Dependency Check
# -------------------------
# Function to check if required commands are available
check_dependencies() {
    local dependencies=("nmap" "curl" "sed" "grep" "ifconfig" "awk" "dd") # "xmlstarlet" 
    missing_dependencies=()

    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "Error: Required command '$cmd' is not installed."
            missing_dependencies+=("$cmd")
        fi
    done

    if [ ${#missing_dependencies[@]} -eq 0 ]; then
        return 0
    else
        echo "The following dependencies are missing: ${missing_dependencies[*]}"
        return 1
    fi
}

# Fix this

# Function to install missing dependencies
install_dependencies() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Attempting to install missing dependencies on macOS using Homebrew..."
        brew install "${missing_dependencies[@]}"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Replace 'ifconfig' with 'net-tools' on Linux
        for i in "${!missing_dependencies[@]}"; do
            if [[ "${missing_dependencies[i]}" == "ifconfig" ]]; then
                missing_dependencies[i]="net-tools"
            fi
        done
        echo "Attempting to install missing dependencies on Linux using apt..."
        sudo apt-get update
        sudo apt-get install -y "${missing_dependencies[@]}"
    else
        echo "Unsupported OS for automatic dependency installation. Please install the missing dependencies manually."
        echo "Missing dependencies: ${missing_dependencies[*]}"
    fi
}

# Function to offer auto setup if dependencies are missing
offer_auto_setup() {
    echo "It looks like some required dependencies are missing."
    read -p "Would you like to attempt automatic installation of the missing dependencies? [y/n] " answer
    if [[ "$answer" == "y" ]]; then
        install_dependencies
        check_dependencies
        if [ $? -ne 0 ]; then
            echo "Some dependencies are still missing. Please install them manually."
            exit 1
        fi
    else
        echo "Please install the missing dependencies manually and run the script again."
        exit 1
    fi
}

add_to_path() {
    local script_path=$(realpath "$0")
    local bin_dir="/usr/local/bin"

    # Check if 'roku' is already in the PATH
    if command -v roku &> /dev/null; then
        # 'roku' command is already available, do nothing
        return 0
    else
        # 'roku' command is not found, proceed with creating a symbolic link
        if [[ -w $bin_dir ]]; then
            echo "Creating symbolic link in $bin_dir..."
            sudo ln -s "$script_path" "$bin_dir/roku"
            echo "Symbolic link created successfully. You can now use the 'roku' command from anywhere."
        else
            echo "You don't have write permission for $bin_dir. Please create the symbolic link manually."
            echo "To create the link manually, use the following command:"
            echo "sudo ln -s \"$script_path\" \"$bin_dir/roku\""
        fi
    fi
}

# # Check if the script is being run for the first time
# if [[ $1 == "--setup" ]]; then
#     add_to_path
#     exit 0
# fi

# -------------------------
# Global Variables
# -------------------------

ip_map=()
selected_ip=""
selected_device_name=""
config_file="${HOME}/roku_config.txt"
config_display_path="${config_file/$HOME/\~}"

# -------------------------
# Main Roku Control Logic
# -------------------------

# Function to send keypress to the Roku device
send_keypress() {
    local key="$1"
    curl -s -d '' "http://$selected_ip:8060/keypress/$key" >/dev/null
}

# Function to launch an app on the Roku device
launch_app() {
    local app_id="$1"
    curl -s -d '' "http://$selected_ip:8060/launch/$app_id" >/dev/null
}

# Function to get the device's subnet in CIDR notation
get_cidr() {
    # Use ifconfig to get the IP address and subnet mask
    ip=$(ifconfig | grep -E 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n1)
    if [ -z "$ip" ]; then
        echo "Error: Unable to retrieve IP address."
        exit 1
    fi
    # Handle hexadecimal subnet masks (common on MacOS)
    mask=$(ifconfig | grep -E 'inet ' | grep -v '127.0.0.1' | awk '{print $4}' | head -n1)
    if [ -z "$mask" ]; then
        echo "Error: Unable to retrieve subnet mask."
        exit 1
    fi
    if [[ $mask == 0x* ]]; then
        mask=$(printf "%d.%d.%d.%d" $((16#${mask:2:2})) $((16#${mask:4:2})) $((16#${mask:6:2})) $((16#${mask:8:2})))
    fi

    # Validate subnet mask format and parse octets
    if [[ ! $mask =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: Invalid format. Must be x.x.x.x"
        exit 1
    fi

    # Parse IP and subnet mask octets
    IFS=. read -r ip1 ip2 ip3 ip4 <<< "$ip"
    IFS=. read -r m1 m2 m3 m4 <<< "$mask"

    # Validate octet ranges
    for octet in "$ip1" "$ip2" "$ip3" "$ip4" "$m1" "$m2" "$m3" "$m4"; do
        if (( octet < 0 || octet > 255 )); then
            echo "Error: Invalid octet value: $octet"
            exit 1
        fi
    done

    # Calculate CIDR prefex with subnet mask
    cidr_prefix=$(echo "$mask" | awk -F. '{
        m=($1*16777216)+($2*65536)+($3*256)+$4; 
        n=0; while(m>0){ n+=m%2; m=int(m/2) } 
        print n
    }')

    # Check CIDR prefix range
    if (( cidr_prefix > 32 )); then
        echo "Error: Invalid subnet mask (CIDR prefix out of range)"
        exit 1
    fi

    # Validate mask bits are contiguous (causes issues with vscode formatter)
    # mask_int=$(( (m1<<24) + (m2<<16) + (m3<<8) + m4 ))
    # expected=$(( (0xFFFFFFFF << (32 - cidr_prefix)) & 0xFFFFFFFF ))
    
    # if (( mask_int != valid_mask_int )); then
    #     echo "Error: Non-contiguous subnet mask"
    #     exit 1
    # fi

    # Error handling if CIDR prefix is empty
    if [ -z "$cidr_prefix" ]; then
        echo "Error: Unable to convert subnet mask to CIDR notation."
        exit 1
    fi

    # Calculate full CIDR address
    echo "$((ip1 & m1)).$((ip2 & m2)).$((ip3 & m3)).$((ip4 & m4))/$cidr_prefix"
}

# Function to scan for Roku devices on the network and store them in ip_map
scan_roku_devices() {
    subnet=$(get_cidr)
    echo "The subnet for this device in CIDR notation is: $subnet."
    echo "Scanning for Roku devices on the network..."
    ip_map=()

    # Use nmap to scan for devices with port 8060 open
    devices=$(nmap -p 8060 "$subnet" --open -oG - | awk '/Status: Up/{print $2}')

    # Check if any devices were found
    if [ -z "$devices" ]; then
        echo "No Roku devices found on the network."
        return 1
    fi

    for ip in $devices; do
        # Get device info from Roku
        device_info=$(curl -s "http://$ip:8060/query/device-info")
        
        # Extract user-device-name and user-device-location using grep and sed
        user_device_name=$(echo "$device_info" | sed -n 's:.*<user-device-name>\(.*\)</user-device-name>.*:\1:p')
        user_device_location=$(echo "$device_info" | sed -n 's:.*<user-device-location>\(.*\)</user-device-location>.*:\1:p')
        
        # Combine name and location
        info="$user_device_name ($user_device_location)"

        # Check if extraction was successful
        if [ -z "$user_device_name" ]; then
            info="Unknown Device"
        fi
        
        # Add to ip_map in the format: ip<TAB>device_name
        ip_map+=("$ip"$'\t'"$info")
    done

    echo "Scan complete. Found ${#ip_map[@]} Roku device(s)."
    echo ""
    return 0
}

# Function to trim leading and trailing whitespace
trim() {
    local var="$*"
    # Remove leading whitespace
    var="${var#"${var%%[![:space:]]*}"}"
    # Remove trailing whitespace
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

# Function to read config_file and populate ip_map array
read_roku_config() {
    ip_map=()
    if [ -f "$config_file" ]; then
        while IFS=$'\t' read -r ip device_name selected_flag; do
            # Trim whitespace using the trim function
            ip=$(trim "$ip")
            device_name=$(trim "$device_name")
            selected_flag=$(trim "$selected_flag")

            # Add to ip_map
            ip_map+=("$ip"$'\t'"$device_name")

            # If this device is selected, set selected_ip and selected_device_name
            if [ "$selected_flag" == "*" ]; then
                selected_ip="$ip"
                selected_device_name="$device_name"
            fi
        done < "$config_file"
    fi
}

# Function to write ip_map array to config_file
write_roku_config() {
    > "$config_file"  # Clear the file
    for entry in "${ip_map[@]}"; do
        # Split the entry into ip and device_name
        IFS=$'\t' read -r ip device_name <<< "$entry"
        # Determine if this is the selected device
        if [ "$ip" == "$selected_ip" ]; then
            selected_flag="*"
        else
            selected_flag=""
        fi
        # Write the line to the config file
        echo -e "$ip\t$device_name\t$selected_flag" >> "$config_file"
    done
}

# Function to select a Roku device
select_roku_device() {
    # Check if config_file exists and populate ip_map
    if [ ! -f "$config_file" ]; then
        echo "$config_display_path file not found. Creating $config_display_path..."
        if ! scan_roku_devices; then
            return
        fi
        write_roku_config
    else
        read_roku_config
    fi

    # Check if ip_map array is empty after reading config_file
    if [ ${#ip_map[@]} -eq 0 ]; then
        echo "No devices found. Please rescan."
        return
    fi

    while true; do
        echo "Select Roku Device: ('R' to Rescan Devices)"
        local i=1
        for entry in "${ip_map[@]}"; do
            IFS=$'\t' read -r ip device_name <<< "$entry"
            echo "$i. $device_name ($ip)"
            ((i++))
        done
        echo "$i. Rescan devices"
        echo ""

        read -rp "Device selection: " device_selection

        # Convert the device_selection input to uppercase
        device_selection=$(echo "$device_selection" | tr '[:lower:]' '[:upper:]')

        case "$device_selection" in "$i" | "R" | "0")
                echo "Rescanning for Roku devices..."
                if ! scan_roku_devices; then
                    echo "No devices found after rescanning."
                    return
                fi
                write_roku_config
                continue
                ;;
        esac

        if [[ "$device_selection" =~ ^[0-9]+$ ]] && (( device_selection >= 1 && device_selection <= ${#ip_map[@]} )); then
            IFS=$'\t' read -r selected_ip selected_device_name <<< "${ip_map[$((device_selection - 1))]}"
            if [ -z "$selected_ip" ]; then
                echo "Invalid selection. Try again."
            else
                # Verify that the selected device is reachable
                if ! curl -s "http://$selected_ip:8060/query/apps" >/dev/null; then
                    echo "The selected device ($selected_ip) is not reachable."
                    echo "Please select a different device."
                    continue
                fi
                echo ""
                # Update the selected device in ip_map
                write_roku_config  # Save the selected device
                break
            fi
        else
            echo "Invalid selection. Try again."
        fi
    done
}

# Function to list apps on the selected device
list_apps() {
    if [ -z "$selected_ip" ]; then
        echo "No device selected. Please select a device first."
        return
    fi

    local apps_xml=$(curl -s "http://$selected_ip:8060/query/apps")
    if [ -z "$apps_xml" ]; then
        echo "Failed to retrieve apps from $selected_ip."
        return
    fi

    declare -A used_keys
    declare -A app_map
    declare -A app_name_map
    local entries=()

    while IFS='|' read -r id name; do
        # Trim and clean the app name
        local trimmed_name=$(echo "$name" | xargs | sed 's/&amp;/\&/g')
        trimmed_name="${trimmed_name#The }"
        trimmed_name="${trimmed_name#A }"

        # Remove non-alphabetic characters and convert to uppercase
        local cleaned_name=$(echo "$trimmed_name" | tr -dc '[:alpha:]' | tr '[:lower:]' '[:upper:]')

        # Initialize key and flag
        local key=""
        local found_unique_key=false

        # Generate a unique key by appending letters from cleaned_name
        for (( i=1; i<=${#cleaned_name}; i++ )); do
            key="${cleaned_name:0:i}"
            if [[ -z "${used_keys[$key]}" ]]; then
                used_keys[$key]=1
                found_unique_key=true
                break
            fi
        done

        # If no unique key could be generated, skip this app
        if [ "$found_unique_key" = false ]; then
            echo "Warning: Unable to generate a unique key for app '$trimmed_name'. Skipping."
            continue
        fi

        local app_id=$(echo "$id" | xargs)

        app_map[$key]="$app_id"
        app_name_map[$key]="$trimmed_name"

        # Prepare the entry for display
        entries+=("$key: $trimmed_name")
    # done < <(echo "$apps_xml" | xmlstarlet sel -t -m "//app" -v "concat(@id, '|', .)" -n)
    done < <(echo "$apps_xml" | awk -F'[><]' '/<app id="/ { 
        split($2, a, "\""); 
        id=a[2]; 
        name=$3; 
        print id "|" name 
    }')

    if [ ${#entries[@]} -eq 0 ]; then
        echo "No apps found on $selected_ip."
        return
    fi

    # Display the apps in a three-column format
    local total=${#entries[@]}
    echo "$total Available Apps:"
    local columns=3
    local rows=$(( (total + columns - 1) / columns ))

    for ((i = 0; i < rows; i++)); do
        for ((j = 0; j < columns; j++)); do
            idx=$(( i + j * rows ))
            if [ $idx -lt $total ]; then
                printf "%-40s" "${entries[idx]}"
            fi
        done
        echo ""
    done

    echo ""
    read -rp "Enter the key of the app to launch or type 'q' to return: " app_selection
    echo ""
    app_selection=$(echo "$app_selection" | tr '[:lower:]' '[:upper:]')
    [[ "$app_selection" == "Q" ]] && { remote_control_commands; return; }

    local app_id=${app_map[$app_selection]}

    if [ -z "$app_id" ]; then
        echo "Invalid app selection. Please try again."
    else
        echo "Launching ${app_name_map[$app_selection]} on $selected_device_name ($selected_ip)..."
        launch_app "$app_id"
        echo "${app_name_map[$app_selection]} launched successfully."
    fi
    sleep 3 && remote_control_commands
}

# Function to display remote control commands
remote_control_commands() {
    clear
    echo ""
    echo "Roku Remote Control"
    echo "-------------------"
    echo "Device Selected: $selected_device_name ($selected_ip)"
    echo "Arrow Keys: Navigate, Space: Play/Pause"
    echo "'e' or Enter: Select, '.': Long Press Select"
    echo "'p': Power, '[': Power On, ']': Power Off"
    echo "'+': Volume Up, '-': Volume Down, 'm': Mute"
    echo "'r': Rewind, 'f': Fast Forward, 'i': Instant Replay"
    echo "'h': Home, 'b' or Backspace: Back, 'o': Options/Info"
    echo "'t': Send Text Input, 's': Send String of Text"
    echo "'a': List Apps, 'd': Select Device, 'l': Locate Remote"
    echo "'x' or 'Esc': Exit Remote Control, '/': Clear Screen"
    echo ""
}

# -------------------------
# Main Function
# -------------------------

# Main function for Roku remote control
roku() {
    # Read the last selected device and IP map on startup
    read_roku_config

    # Verify that the selected device is reachable
    if [ -n "$selected_ip" ]; then
        # echo "Checking if the selected device ($selected_ip) is reachable..."
        if ! curl -s "http://$selected_ip:8060/query/apps" >/dev/null; then
            echo "The selected device ($selected_ip) is not reachable."
            selected_ip=""
            selected_device_name=""
        else
            echo "The selected device ($selected_ip) is reachable."
        fi
    fi

    # Ensure a device is selected
    if [ -z "$selected_ip" ]; then
        echo "No device selected or device is unreachable. Please select a device."
        select_roku_device
        if [ -z "$selected_ip" ]; then
            echo "No device selected."
            echo "Exiting remote control."
            return
        fi
    fi

    remote_control_commands

    while IFS= read -r -n1 -s key; do
        if [ -z "$key" ]; then
            send_keypress "Select"  # Enter key for Select
            continue
        fi

        case "$key" in
            $'\x1b') read -r -n1 -t 0.1 -s key2  # Read the next character with a timeout
                if [[ -z "$key2" ]]; then
                    # No additional input after escape, so it's just the escape key
                    echo "Exiting remote control."; echo ""
                    break
                elif [[ "$key2" == "[" ]]; then
                    read -r -n1 -s key3  # Read the third character to determine which arrow key
                    case "$key3" in
                        'A') send_keypress "Up" ;;    # Arrow up
                        'B') send_keypress "Down" ;;  # Arrow down
                        'C') send_keypress "Right" ;; # Arrow right
                        'D') send_keypress "Left" ;;  # Arrow left
                        *) ;;  # Ignore unrecognized sequences
                    esac
                else
                    # Unrecognized escape sequence, ignore or handle as needed
                    :
                fi
                ;;
            'e' | $'\n' | $'\r') send_keypress "Select" ;;  # Enter or 'e'
            '.') curl -s -d '' "http://$selected_ip:8060/keydown/Select" ;;
            ' ') send_keypress "Play" ;;
            '+' | '=') send_keypress "VolumeUp" ;;
            '-' | '_') send_keypress "VolumeDown" ;;
            'm') send_keypress "VolumeMute" ;;
            'o') send_keypress "Info" ;;
            'p' | '\') send_keypress "Power" ;;
            '[') send_keypress "PowerOn" ;;
            ']') send_keypress "PowerOff" ;;
            'r') send_keypress "Rev" ;;
            'f') send_keypress "Fwd" ;;
            'l') send_keypress "FindRemote" ;;
            'i') send_keypress "InstantReplay" ;;
            'h') send_keypress "Home" ;;
            'b' | $'\x7f') send_keypress "Back" ;;  # Backspace or 'b'
            # App Shortcuts 
            '1') launch_app "13535" ;; # Plex
            'y' | '2') launch_app "837" ;; # YouTube
            'n' | '3') launch_app "12" ;; # Netflix
            '4') launch_app "61322" ;; # Max
            '5') launch_app "551012" ;; # Apple TV
            's')
                echo -n "Enter string of text to send: "
                read -r text
                for (( i=0; i<${#text}; i++ )); do
                    char="${text:i:1}"
                    # URL-encode the character to handle special characters
                    char_encoded=$(printf '%%%02X' "'$char")
                    # Send the character
                    send_keypress "Lit_$char_encoded"
                done
                echo "Text '$text' sent to $selected_device_name ($selected_ip)."
                ;;
            't')
                echo "Entering text mode. Press Esc to exit."

                # Set terminal to raw mode to capture key presses without waiting for Enter
                stty -echo -icanon time 0 min 1

                while true; do
                    # Read a single character
                    char=$(dd bs=1 count=1 2>/dev/null)
                    # IFS= read -r -n1 -s char # Alternative (slower?) method to read a single character
                    
                    case "$char" in
                        # Check for Escape (ASCII 27) to exit
                        $'\x1b')
                            read -r -n3 -t 0.1 -s text # Ignore any escaped key sequences
                            break
                            ;;
                        # Handle Backspace (ASCII 127)
                        $'\x7f')
                            send_keypress "Backspace"
                            ;;
                        # Handle Enter (ASCII 10 or 13 or empty string)
                        $'\x0a' | $'\x0d' | '')
                            send_keypress "Enter"
                            ;;
                        *)
                            # URL-encode the character to handle special characters
                            char_encoded=$(printf '%%%02X' "'$char")
                            # Send the keypress to the Roku
                            send_keypress "Lit_$char_encoded"
                            ;;
                    esac
                done

                # Restore terminal settings
                stty sane
                remote_control_commands
                ;;
            'a')
                list_apps
                ;;
            'd')
                # Key to select a different device
                select_roku_device
                if [ -z "$selected_ip" ]; then
                    echo "No device selected. Continuing with previous device."
                else
                    # Verify that the new selected device is reachable
                    if ! curl -s "http://$selected_ip:8060/query/apps" >/dev/null; then
                        echo "The selected device ($selected_ip) is not reachable."
                        selected_ip=""
                        selected_device_name=""
                    else
                        echo "Device switched to $selected_device_name ($selected_ip)."
                        write_roku_config  # Save the new selected device
                    fi
                fi
                sleep 1 && remote_control_commands
                ;;
            '/' | '?') clear ; remote_control_commands ;;
            'x' | 'q') echo "Exiting remote control."; echo ""; break ;;
            *) echo "Invalid command. Try again." ;;
        esac
    done
}

# -------------------------
# Start the Roku Remote Control
# -------------------------

# First, check if all dependencies are installed
check_dependencies

# If any dependencies are missing, offer auto setup
if [ $? -ne 0 ]; then
    offer_auto_setup
fi

# If all dependencies are fine, proceed with the rest of the script
roku
