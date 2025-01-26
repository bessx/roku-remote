# Roku Remote Control Script

This script allows you to remotely control Roku devices on your local network using bash. It provides functions to send keypresses, launch apps, and perform other Roku remote actions, such as volume control, text input, and scanning for devices.

## Features
- Automatically discovers Roku devices on your network.
- Send remote control keypresses (e.g., navigation, play/pause, volume control).
- Launch apps installed on your Roku device.
- Easily switch between multiple Roku devices.
- Text input functionality to send characters or strings to the Roku device.

## Dependencies
Before running this script, ensure you have the following utilities installed:
- nmap
- curl
- sed
- grep
- ifconfig
- awk
- dd
- (Optional) xmlstarlet for XML parsing (currently not used).

### Installing Dependencies
On most systems, you can install the dependencies with the following commands:

Ubuntu/Debian:

```bash
sudo apt update sudo apt install nmap curl sed grep net-tools gawk coreutils
```


macOS (with Homebrew):

```bash
brew install nmap curl gawk coreutils
```

## Setup

1. **Make the script executable:**

```bash
chmod +x roku.sh
```
2. **Add the script to your system's PATH (optional):**
You can create a symbolic link to make it easier to run the script from anywhere:

```bash
sudo ln -s /path/to/roku.sh /usr/local/bin/roku
roku
```


## Usage

1. **Run the script:**
```bash
./roku.sh
```


2. **Select a Roku device:**
The script will scan for Roku devices on your network. If any are found, you will be prompted to select a device.

3. **Control the Roku:**
Once a device is selected, you can use the following commands to control the Roku device:

- Arrow Keys: Navigate
- Enter or `e`: Select
- Space: Play/Pause
- `p`: Power toggle
- `+` or `=`: Volume Up
- `-`: Volume Down
- `m`: Mute
- `r`: Rewind
- `f`: Fast Forward
- `a`: List installed apps
- `t`: Send text input
- `d`: Switch to a different Roku device
- `x` or `q`: Exit

4. **Launching Apps:**
You can launch apps on the selected Roku by typing their corresponding key after listing apps (`a` command). 

## Configuration

The script uses a configuration file `roku_config.txt` to remember the last selected device and save its details. When a device is selected, its IP and name are stored, making it easy to reconnect to the same device on future runs.

## Limitations

- The script assumes the Roku device uses port 8060 for communication (default for Roku devices).
- The device must be on the same local network for it to be discovered.
- Some apps may not generate a unique key for launching due to name conflicts or special characters.

## Troubleshooting

- If no Roku devices are found, ensure your device is powered on and connected to the same network.
- Ensure the required dependencies are installed and available in your system's PATH.

---

Enjoy your new Roku remote control! If you encounter any issues, feel free to check the script's error messages for guidance on missing dependencies or unreachable devices.