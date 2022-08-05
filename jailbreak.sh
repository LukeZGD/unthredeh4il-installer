#!/bin/bash
trap "Clean" EXIT
trap "Clean; exit 1" INT TERM

cd "$(dirname $0)"

if [[ $1 != "NoColor" ]]; then
    TERM=xterm-256color
    Color_R=$(tput setaf 9)
    Color_G=$(tput setaf 10)
    Color_B=$(tput setaf 12)
    Color_Y=$(tput setaf 11)
    Color_N=$(tput sgr0)
fi

Clean() {
    rm -rf tmp/
    kill $iproxyPID 2>/dev/null
}

Echo() {
    echo "${Color_B}$1 ${Color_N}"
}

Error() {
    echo -e "\n${Color_R}[Error] $1 ${Color_N}"
    [[ -n $2 ]] && echo "${Color_R}* $2 ${Color_N}"
    echo
    ExitWin 1
}

Input() {
    echo "${Color_Y}[Input] $1 ${Color_N}"
}

Log() {
    echo "${Color_G}[Log] $1 ${Color_N}"
}

ExitWin() {
    if [[ $platform == "win" ]]; then
        echo
        Input "Press Enter/Return to exit."
        read -s
    fi
    exit $1
}

SetToolPaths() {
    ping="ping -c1"
    sha1sum="$(which sha1sum 2>/dev/null)"
    if [[ $OSTYPE == "linux"* ]]; then
        . /etc/os-release
        platform="linux"
    elif [[ $OSTYPE == "darwin"* ]]; then
        platform="macos"
        sha1sum="$(which shasum)"
    elif [[ $OSTYPE == "msys" ]]; then
        platform="win"
        ping="ping -n 1"
    fi
    MPath="./resources/libimobiledevice_$platform"
    partialzip="../resources/bin/partialzip_$platform"
    xpwntool="../resources/bin/xpwntool_$platform"
    hfsplus="../resources/bin/hfsplus_$platform"
    iBoot32Patcher="../resources/bin/iBoot32Patcher_$platform"
    pwnDFUTool="./resources/bin/pwnedDFU_$platform"
    ideviceinfo="$MPath/ideviceinfo"
    iproxy="$MPath/iproxy"
    irecovery="$MPath/irecovery"
    SSH="$(which ssh) -F ./resources/ssh_config"
}

SaveFile() {
    Log "Downloading $2..."
    curl -L $1 -o $2
    local SHA1=$($sha1sum $2 | awk '{print $1}')
    if [[ $SHA1 != $3 ]]; then
        Error "Verifying $2 failed. The downloaded file may be corrupted or incomplete. Please run the script again" \
        "SHA1sum mismatch. Expected $3, got $SHA1"
    fi
}

InstallDepends() {
    local libimobiledevice

    mkdir tmp 2>/dev/null
    cd tmp

    Log "Installing dependencies..."
    if [[ $platform == "linux" ]]; then
        Echo "* The install script will be installing dependencies from your distribution's package manager"
        Echo "* Enter your user password when prompted"
        Input "Press Enter/Return to continue (or press Ctrl+C to cancel)"
        read -s
    fi

    if [[ -e /etc/debian_version ]]; then
        DebianVer=$(cat /etc/debian_version)
        if [[ $DebianVer == *"sid" ]]; then
            DebianVer="sid"
        else
            DebianVer="$(echo $DebianVer | cut -c -2)"
        fi
    fi

    if [[ $ID == "arch" || $ID_LIKE == "arch" || $ID == "artix" ]]; then
        sudo pacman -Sy --noconfirm --needed base-devel bsdiff curl libimobiledevice udev unzip usbmuxd usbutils

    elif [[ -n $UBUNTU_CODENAME && $VERSION_ID == "2"* ]] ||
         (( DebianVer >= 11 )) || [[ $DebianVer == "sid" ]]; then
        [[ -n $UBUNTU_CODENAME ]] && sudo add-apt-repository -y universe
        sudo apt update
        sudo apt install -y curl libimobiledevice6 unzip usbmuxd usbutils
        sudo systemctl enable --now udev systemd-udevd usbmuxd 2>/dev/null

    elif [[ $ID == "fedora" ]] && (( VERSION_ID >= 36 )); then
        ln -sf /usr/lib64/libbz2.so.1.* ../resources/lib/libbz2.so.1.0
        sudo dnf install -y ca-certificates libimobiledevice systemd udev usbmuxd
        sudo ln -sf /etc/pki/tls/certs/ca-bundle.crt /etc/pki/tls/certs/ca-certificates.crt

    elif [[ $ID == "opensuse-tumbleweed" || $PRETTY_NAME == *"Leap 15.4" ]]; then
        [[ $ID == "opensuse-leap" ]] && ln -sf /lib64/libreadline.so.7 ../resources/lib/libreadline.so.8
        sudo zypper -n in curl libimobiledevice-1_0-6 usbmuxd

    elif [[ $platform == "macos" ]]; then
        xcode-select --install
        libimobiledevice=("https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/libimobiledevice_macos.zip" "66a49e4f69757a3d9dc51109a8e4651020bfacb8")

    elif [[ $platform == "win" ]]; then
        pacman -Sy --noconfirm --needed ca-certificates curl openssh unzip zip
        libimobiledevice=("https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/libimobiledevice_win.zip" "75ae3af3347b89107f0f6b7e41fde42e6ccdd404")

    else
        Error "Distro not detected/supported by the install script." "See the repo README for supported OS versions/distros"
    fi

    if [[ $platform == "linux" ]]; then
        libimobiledevice=("https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/libimobiledevice_linux.zip" "fc5e714adf6fa72328d3e1ddea4e633f370559a4")
        # from linux_fix script by Cryptiiiic
        sudo systemctl enable --now systemd-udevd usbmuxd 2>/dev/null
        echo "QUNUSU9OPT0iYWRkIiwgU1VCU1lTVEVNPT0idXNiIiwgQVRUUntpZFZlbmRvcn09PSIwNWFjIiwgQVRUUntpZFByb2R1Y3R9PT0iMTIyWzI3XXwxMjhbMC0zXSIsIE9XTkVSPSJyb290IiwgR1JPVVA9InVzYm11eGQiLCBNT0RFPSIwNjYwIiwgVEFHKz0idWFjY2VzcyIKCkFDVElPTj09ImFkZCIsIFNVQlNZU1RFTT09InVzYiIsIEFUVFJ7aWRWZW5kb3J9PT0iMDVhYyIsIEFUVFJ7aWRQcm9kdWN0fT09IjEzMzgiLCBPV05FUj0icm9vdCIsIEdST1VQPSJ1c2JtdXhkIiwgTU9ERT0iMDY2MCIsIFRBRys9InVhY2Nlc3MiCgoK" | base64 -d | sudo tee /usr/lib/udev/rules.d/39-libirecovery.rules >/dev/null 2>/dev/null
        sudo chown root:root /usr/lib/udev/rules.d/39-libirecovery.rules
        sudo chmod 0644 /usr/lib/udev/rules.d/39-libirecovery.rules
        sudo udevadm control --reload-rules
    fi

    SaveFile ${libimobiledevice[0]} libimobiledevice.zip ${libimobiledevice[1]}
    mkdir ../resources/libimobiledevice_$platform
    Log "Extracting libimobiledevice..."
    unzip -q libimobiledevice.zip -d ../resources/libimobiledevice_$platform
    chmod +x ../resources/libimobiledevice_$platform/*
    touch ../resources/first_run

    cd ..
    Log "Install script done! Please run the script again to proceed"
    Log "If your iOS device is plugged in, unplug and replug your device"
    ExitWin 0
}

FindDevice() {
    local DeviceIn
    local i=0
    local USB
    local Timeout=5

    Log "Finding device in $1 mode, please wait..."
    if [[ $1 == "Restore" ]]; then
        Timeout=30
        Echo "* This may take a while."
    fi
    while (( i < Timeout )); do
        if [[ $1 == "Restore" ]]; then
            ideviceinfo2=$($ideviceinfo -s)
            [[ $? == 0 ]] && DeviceIn=1
        else
            [[ $($irecovery -q 2>/dev/null | grep -w "MODE" | cut -c 7-) == "$1" ]] && DeviceIn=1
        fi
        if [[ $DeviceIn == 1 ]]; then
            Log "Found device in $1 mode."
            DeviceState="$1"
            break
        fi
        sleep 1
        ((i++))
    done

    if [[ $DeviceIn != 1 ]]; then
        Error "Failed to find device in $1 mode. (Timed out)"
    fi
}

GetDeviceValues() {
    Log "Finding device in DFU mode..."
    DeviceState="$($irecovery -q 2>/dev/null | grep -w "MODE" | cut -c 7-)"
    if [[ $DeviceState == "DFU" || $DeviceState == "Recovery" ]]; then
        local ProdCut=7
        ProductType=$($irecovery -qv 2>&1 | grep "Connected to iP" | cut -c 14-)
        [[ $(echo $ProductType | cut -c 3) == 'h' ]] && ProdCut=9
        ProductType=$(echo $ProductType | cut -c -$ProdCut)
    fi

    if [[ $DeviceState != "DFU" ]]; then
        Error "Device cannot be found, or is not in DFU mode." \
        "Please connect a supported device in DFU mode and run the script again"
    fi

    if [[ $ProductType != "iPad1,1" && $ProductType != "iPhone2,1" && $ProductType != "iPhone3,1" &&
          $ProductType != "iPhone3,3" && $ProductType != "iPod3,1" && $ProductType != "iPod4,1" ]]; then
        Error "Your device $ProductType is not supported."
    fi

    Log "Found $ProductType in DFU mode."
    Component=(iBSS iBEC AppleLogo DeviceTree Kernelcache Ramdisk)
    File=()
    IV=()
    Key=()
    . ./resources/$ProductType.sh
}

EnterPwnDFU() {
    if [[ $platform == "win" ]]; then
        Echo "* Make sure that your device is already in pwnDFU mode."
        Echo "* If your device is not in pwnDFU mode, the install will not work!"
        Input "Press Enter/Return to continue (or press Ctrl+C to cancel)"
        read -s
        return
    fi
    Log "Entering pwnDFU mode with: $pwnDFUTool"
    $pwnDFUTool -p
    pwnDFUDevice=$?
    pwnD=$($irecovery -q | grep -c "PWND")
    if [[ $pwnDFUDevice != 0 ]]; then
        Error "Failed to enter pwnDFU mode. Please run the script again" \
        "Exit DFU mode first by holding the TOP and HOME buttons for about 15 seconds."
    elif [[ $pwnD != 1 ]]; then
        Error "Your device is not in pwnDFU mode, cannot proceed. Note that kDFU mode will NOT work!" \
        "Exit DFU mode by holding the TOP and HOME buttons for about 15 seconds."
    else
        Log "Device in pwnDFU mode detected."
    fi
}

Main() {
    local Selection=("Jailbreak Device" "Install Untether Package" "(Re-)Install Dependencies" "(Any other key to exit)")

    clear
    Echo "*** unthredeh4il-installer ***"
    Echo "* Script by LukeZGD"
    echo

    if [[ $EUID == 0 ]]; then
        Error "Running the script as root is not allowed."
    fi

    if [[ ! -d ./resources ]]; then
        Error "resources folder cannot be found. Replace resources folder and try again." \
        "If resources folder is present try removing spaces from path/folder name"
    fi

    if [[ -d .git ]]; then
        Echo "Version: $(git rev-parse HEAD)"
    fi

    SetToolPaths
    if [[ ! $platform ]]; then
        Error "Platform unknown/not supported."
    fi

    chmod +x ./resources/bin/*
    if [[ $? != 0 ]]; then
        Error "A problem with file permissions has been detected, cannot proceed."
    fi

    Log "Checking Internet connection..."
    $ping 8.8.8.8 >/dev/null
    if [[ $? != 0 ]]; then
        Log "WARNING - Please check your Internet connection before proceeding."
    fi

    if [[ $platform == "macos" && $(uname -m) != "x86_64" ]]; then
        Log "Apple Silicon Mac detected. Support may be limited, proceed at your own risk."
    elif [[ $(uname -m) != "x86_64" ]]; then
        Error "Only 64-bit (x86_64) distributions are supported."
    fi

    if [[ $1 == "Install" || ! -e ./resources/first_run ]]; then
        Clean
        InstallDepends
    fi

    GetDeviceValues
    Clean
    mkdir tmp 2>/dev/null

    echo
    Echo "*** Main Menu ***"
    Input "Select an option:"
    select opt in "${Selection[@]}"; do
    case $opt in
        "Jailbreak Device" ) Mode="Jailbreak"; EnterPwnDFU; break;;
        "Install Untether Package" ) Mode="Package"; break;;
        "(Re-)Install Dependencies" ) InstallDepends;;
        * ) exit 0;;
    esac
    done

    $Mode
    ExitWin 0
}

Jailbreak() {
    if [[ -d ./resources/SSH-Ramdisk_$ProductType ]]; then
        Log "SSH-Ramdisk_$ProductType exists"
    else
        RamdiskCreate
    fi
    RamdiskBoot

    Log "Running iproxy for SSH..."
    $iproxy 2222 22 &
    iproxyPID=$!
    sleep 2

    Log "Running commands..."
    Echo "* Please enter the root password \"alpine\" when prompted"
    $SSH -p 2222 root@127.0.0.1 "/bin/install.sh"
    if [[ $? == 1 ]]; then
        Error "Cannot connect to device via SSH."
    fi

    Log "Done!"
}

Package() {
    Echo "* If you are already jailbroken using redsn0w, no need to use this script."
    Echo "* Just get the untether package .deb from the resources folder and install that to your device"
}

RamdiskCreate() {
    Log "Creating ramdisk"
    mkdir -p saved/$ProductType
    cd tmp
    for i in {0..5}; do
        if [[ -e ../saved/$ProductType/${Component[$i]} ]]; then
            cp ../saved/$ProductType/${Component[$i]} .
        else
            $partialzip $IPSW_URL ${File[$i]} ${Component[$i]}
            cp ${Component[$i]} ../saved/$ProductType
        fi
        $xpwntool ${Component[$i]} ${Component[$i]}.dec -iv ${IV[$i]} -k ${Key[$i]} -decrypt
        rm ${Component[$i]}
    done
    $xpwntool Ramdisk.dec Ramdisk.raw
    if [[ $platform == "macos" ]]; then
        hdiutil resize -size 50MB Ramdisk.raw
        mkdir ramdisk_mountpoint
        hdiutil attach -mountpoint ramdisk_mountpoint/ Ramdisk.raw
        tar -xvf ../resources/ssh.tar -C ramdisk_mountpoint/
        hdiutil detach ramdisk_mountpoint
    else
        $hfsplus Ramdisk.raw grow 50000000
        $hfsplus Ramdisk.raw untar ../resources/ssh.tar
    fi
    $xpwntool Ramdisk.raw Ramdisk.dmg -t Ramdisk.dec

    $xpwntool iBSS.dec iBSS.raw
    $iBoot32Patcher iBSS.raw iBSS.patched -r
    $xpwntool iBSS.patched iBSS -t iBSS.dec

    $xpwntool iBEC.dec iBEC.raw
    $iBoot32Patcher iBEC.raw iBEC.patched -r -d -b "rd=md0 -v amfi=0xff cs_enforcement_disable=1"
    $xpwntool iBEC.patched iBEC -t iBEC.dec

    mkdir -p ../resources/SSH-Ramdisk_$ProductType
    mv iBSS iBEC AppleLogo.dec DeviceTree.dec Kernelcache.dec Ramdisk.dmg ../resources/SSH-Ramdisk_$ProductType
    cd ..
}

RamdiskBoot() {
    local irecovery="../../$irecovery"
    local ideviceinfo="../../$ideviceinfo"
    cd resources/SSH-Ramdisk_$ProductType

    Log "Sending iBSS"
    $irecovery -f iBSS
    sleep 2
    Log "Sending iBEC"
    $irecovery -f iBEC
    FindDevice "Recovery"

    Log "Booting..."
    $irecovery -f Ramdisk.dmg
    $irecovery -c ramdisk
    $irecovery -f DeviceTree.dec
    $irecovery -c devicetree
    $irecovery -f Kernelcache.dec
    $irecovery -c bootx
    FindDevice "Restore"
    cd ../..
}

Main
