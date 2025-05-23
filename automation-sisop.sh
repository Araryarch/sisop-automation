#!/bin/bash

# OS Booting Automation Script
# Modul 3 - Operating System Booting
# Author: Automated Script for Learning Purposes

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_section() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Function to check if running as root for certain operations
check_sudo() {
    if [[ $EUID -eq 0 ]]; then
        print_warning "Script is running as root. This is needed for some operations."
    fi
}

# Function to install dependencies
install_dependencies() {
    print_section "Installing Dependencies"
    
    print_status "Updating package lists..."
    sudo apt -y update
    
    print_status "Installing required packages..."
    sudo apt -y install qemu-system build-essential bison flex libelf-dev \
                       libssl-dev bc grub-common grub-pc libncurses-dev \
                       mtools grub-pc-bin xorriso tmux busybox-static \
                       wget cpio gzip openssl
    
    print_status "Dependencies installed successfully!"
}

# Function to setup project directory
setup_directory() {
    print_section "Setting Up Project Directory"
    
    if [ -d "osboot" ]; then
        print_warning "Directory 'osboot' already exists. Removing it..."
        rm -rf osboot
    fi
    
    mkdir -p osboot
    cd osboot
    print_status "Project directory created and entered: $(pwd)"
}

# Function to download and extract kernel
download_kernel() {
    print_section "Downloading Linux Kernel"
    
    if [ ! -f "linux-6.1.1.tar.xz" ]; then
        print_status "Downloading Linux kernel 6.1.1..."
        wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.1.1.tar.xz
    else
        print_status "Kernel archive already exists, skipping download"
    fi
    
    if [ ! -d "linux-6.1.1" ]; then
        print_status "Extracting kernel source..."
        tar -xf linux-6.1.1.tar.xz
    else
        print_status "Kernel source already extracted"
    fi
}

# Function to configure kernel
configure_kernel() {
    print_section "Configuring Linux Kernel"
    
    cd linux-6.1.1
    
    print_status "Creating minimal kernel configuration..."
    make tinyconfig
    
    print_status "Applying additional kernel configurations..."
    
    # Enable required kernel options
    cat >> .config << EOF
CONFIG_64BIT=y
CONFIG_PRINTK=y
CONFIG_FUTEX=y
CONFIG_INITRAMFS_SOURCE=""
CONFIG_CGROUPS=y
CONFIG_BLOCK=y
CONFIG_BLK_DEV_BSG=y
CONFIG_PARTITION_ADVANCED=y
CONFIG_TTY=y
CONFIG_VIRTIO_CONSOLE=y
CONFIG_DEVMEM=y
CONFIG_VIRTIO_NET=y
CONFIG_ATA=y
CONFIG_VIRTIO_BLK=y
CONFIG_BLK_DEV_LOOP=y
CONFIG_BLK_DEV_RAM=y
CONFIG_VIRTIO_DRIVERS=y
CONFIG_VIRT_DRIVERS=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
CONFIG_FUSE_FS=y
CONFIG_EXT3_FS=y
CONFIG_EXT4_FS=y
CONFIG_EXT2_FS=y
CONFIG_VIRTIO_FS=y
CONFIG_AUTOFS4_FS=y
CONFIG_PROC_FS=y
CONFIG_PROC_SYSCTL=y
CONFIG_SYSFS=y
CONFIG_UNIX=y
CONFIG_INET=y
CONFIG_NET=y
EOF

    print_status "Finalizing kernel configuration..."
    make olddefconfig
    
    cd ..
}

# Function to compile kernel
compile_kernel() {
    print_section "Compiling Linux Kernel"
    
    cd linux-6.1.1
    
    print_status "Starting kernel compilation (this may take a while)..."
    make -j$(nproc)
    
    print_status "Copying compiled kernel..."
    cp arch/x86/boot/bzImage ..
    
    cd ..
    print_status "Kernel compilation completed! bzImage created."
}

# Function to create single user root filesystem
create_single_user_fs() {
    print_section "Creating Single User Root Filesystem"
    
    print_status "Becoming root for filesystem operations..."
    
    # Create the filesystem creation script
    cat > create_single_user.sh << 'EOF'
#!/bin/bash
set -e

echo "Creating single user filesystem..."

# Remove existing directory if it exists
rm -rf myramdisk_single

# Create directory structure
mkdir -p myramdisk_single/{bin,dev,proc,sys}

# Copy device files
cp -a /dev/null myramdisk_single/dev/
cp -a /dev/tty* myramdisk_single/dev/ 2>/dev/null || true
cp -a /dev/zero myramdisk_single/dev/
cp -a /dev/console myramdisk_single/dev/

# Copy busybox and install utilities
cp /usr/bin/busybox myramdisk_single/bin/
cd myramdisk_single/bin
./busybox --install .
cd ..

# Create init script
cat > init << 'INIT_EOF'
#!/bin/sh
echo "Starting Single User System..."
/bin/mount -t proc none /proc
/bin/mount -t sysfs none /sys
echo "Welcome to Single User BusyBox System!"
exec /bin/sh
INIT_EOF

chmod +x init

# Create compressed initramfs
find . | cpio -oHnewc | gzip > ../myramdisk_single.gz

cd ..
echo "Single user filesystem created: myramdisk_single.gz"
EOF

    chmod +x create_single_user.sh
    sudo bash create_single_user.sh
    
    print_status "Single user root filesystem created!"
}

# Function to create multi user root filesystem
create_multi_user_fs() {
    print_section "Creating Multi User Root Filesystem"
    
    # Generate password hash
    print_status "Generating password hash..."
    PASSWORD_HASH=$(openssl passwd -1 "password123")
    
    # Create the filesystem creation script
    cat > create_multi_user.sh << EOF
#!/bin/bash
set -e

echo "Creating multi user filesystem..."

# Remove existing directory if it exists
rm -rf myramdisk_multi

# Create directory structure
mkdir -p myramdisk_multi/{bin,dev,proc,sys,etc,root,home/user1}

# Copy device files
cp -a /dev/null myramdisk_multi/dev/
cp -a /dev/tty* myramdisk_multi/dev/ 2>/dev/null || true
cp -a /dev/zero myramdisk_multi/dev/
cp -a /dev/console myramdisk_multi/dev/

# Copy busybox and install utilities
cp /usr/bin/busybox myramdisk_multi/bin/
cd myramdisk_multi/bin
./busybox --install .
cd ..

# Create passwd file
cat > etc/passwd << 'PASSWD_EOF'
root:${PASSWORD_HASH}:0:0:root:/root:/bin/sh
user1:${PASSWORD_HASH}:1001:100:user1:/home/user1:/bin/sh
PASSWD_EOF

# Create group file
cat > etc/group << 'GROUP_EOF'
root:x:0:
bin:x:1:root
sys:x:2:root
tty:x:5:root,user1
disk:x:6:root
wheel:x:10:root,user1
users:x:100:user1
GROUP_EOF

# Create hostname file
echo "multilinux" > etc/hostname

# Create init script for multi-user
cat > init << 'INIT_EOF'
#!/bin/sh
echo "Starting Multi User System..."
/bin/mount -t proc none /proc
/bin/mount -t sysfs none /sys
/bin/mount -t devtmpfs none /dev 2>/dev/null || true

echo "Multi User Linux System"
echo "Default login:"
echo "  Username: root or user1"
echo "  Password: password123"
echo ""

# Start getty for login
while true; do
    /sbin/getty -L tty1 115200 vt100
    sleep 1
done
INIT_EOF

chmod +x init

# Create compressed initramfs
find . | cpio -oHnewc | gzip > ../myramdisk_multi.gz

cd ..
echo "Multi user filesystem created: myramdisk_multi.gz"
EOF

    chmod +x create_multi_user.sh
    sudo bash create_multi_user.sh
    
    print_status "Multi user root filesystem created!"
    print_status "Default credentials - Username: root/user1, Password: password123"
}

# Function to test with QEMU
test_with_qemu() {
    print_section "Testing with QEMU"
    
    local fs_type=$1
    local initrd_file=""
    
    if [ "$fs_type" = "single" ]; then
        initrd_file="myramdisk_single.gz"
        print_status "Testing Single User System with QEMU..."
    elif [ "$fs_type" = "multi" ]; then
        initrd_file="myramdisk_multi.gz"
        print_status "Testing Multi User System with QEMU..."
    else
        print_error "Invalid filesystem type specified"
        return 1
    fi
    
    if [ ! -f "$initrd_file" ]; then
        print_error "Initrd file $initrd_file not found!"
        return 1
    fi
    
    print_status "Starting QEMU emulation..."
    print_warning "Press Ctrl+A then X to exit QEMU"
    print_warning "Or run 'pkill -f qemu' from another terminal"
    
    qemu-system-x86_64 \
        -smp 2 \
        -m 256 \
        -display curses \
        -vga std \
        -kernel bzImage \
        -initrd "$initrd_file"
}

# Function to create ISO
create_iso() {
    print_section "Creating Bootable ISO"
    
    local fs_type=$1
    local initrd_file=""
    local iso_name=""
    
    if [ "$fs_type" = "single" ]; then
        initrd_file="myramdisk_single.gz"
        iso_name="mylinux_single.iso"
    elif [ "$fs_type" = "multi" ]; then
        initrd_file="myramdisk_multi.gz"
        iso_name="mylinux_multi.iso"
    else
        print_error "Invalid filesystem type specified"
        return 1
    fi
    
    print_status "Creating ISO structure..."
    rm -rf mylinuxiso
    mkdir -p mylinuxiso/boot/grub
    
    print_status "Copying kernel and initrd..."
    cp bzImage mylinuxiso/boot/
    cp "$initrd_file" mylinuxiso/boot/myramdisk.gz
    
    print_status "Creating GRUB configuration..."
    cat > mylinuxiso/boot/grub/grub.cfg << EOF
set timeout=5
set default=0

menuentry "MyLinux ($fs_type user)" {
    linux /boot/bzImage
    initrd /boot/myramdisk.gz
}
EOF
    
    print_status "Building ISO file..."
    grub-mkrescue -o "$iso_name" mylinuxiso
    
    print_status "ISO created: $iso_name"
}

# Function to test ISO with QEMU
test_iso_with_qemu() {
    print_section "Testing ISO with QEMU"
    
    local iso_file=$1
    
    if [ ! -f "$iso_file" ]; then
        print_error "ISO file $iso_file not found!"
        return 1
    fi
    
    print_status "Starting QEMU with ISO: $iso_file"
    print_warning "Press Ctrl+A then X to exit QEMU"
    
    qemu-system-x86_64 \
        -smp 2 \
        -m 256 \
        -display curses \
        -vga std \
        -cdrom "$iso_file"
}

# Function to cleanup
cleanup() {
    print_section "Cleanup"
    
    print_status "Removing temporary files..."
    rm -f create_single_user.sh create_multi_user.sh
    rm -rf myramdisk_single myramdisk_multi mylinuxiso
    
    print_status "Cleanup completed!"
}

# Function to show menu
show_menu() {
    echo -e "\n${BLUE}OS Booting Automation Menu${NC}"
    echo "=================================="
    echo "1. Full Setup (Install deps + Build kernel + Create filesystems + Create ISOs)"
    echo "2. Install Dependencies Only"
    echo "3. Build Kernel Only"
    echo "4. Create Single User Filesystem"
    echo "5. Create Multi User Filesystem"
    echo "6. Test Single User with QEMU"
    echo "7. Test Multi User with QEMU"
    echo "8. Create Single User ISO"
    echo "9. Create Multi User ISO"
    echo "10. Test Single User ISO with QEMU"
    echo "11. Test Multi User ISO with QEMU"
    echo "12. Cleanup"
    echo "13. Exit"
    echo "=================================="
    echo -n "Enter your choice [1-13]: "
}

# Main function
main() {
    print_section "OS Booting Automation Script"
    print_status "Starting automation for Operating System Booting module"
    
    # Check if we're in the right directory
    if [ "$(basename $(pwd))" = "osboot" ]; then
        print_status "Already in osboot directory"
    fi
    
    while true; do
        show_menu
        read choice
        
        case $choice in
            1)
                install_dependencies
                setup_directory
                download_kernel
                configure_kernel
                compile_kernel
                create_single_user_fs
                create_multi_user_fs
                create_iso "single"
                create_iso "multi"
                print_status "Full setup completed!"
                ;;
            2)
                install_dependencies
                ;;
            3)
                if [ ! -d "osboot" ]; then
                    setup_directory
                fi
                download_kernel
                configure_kernel
                compile_kernel
                ;;
            4)
                create_single_user_fs
                ;;
            5)
                create_multi_user_fs
                ;;
            6)
                test_with_qemu "single"
                ;;
            7)
                test_with_qemu "multi"
                ;;
            8)
                create_iso "single"
                ;;
            9)
                create_iso "multi"
                ;;
            10)
                test_iso_with_qemu "mylinux_single.iso"
                ;;
            11)
                test_iso_with_qemu "mylinux_multi.iso"
                ;;
            12)
                cleanup
                ;;
            13)
                print_status "Exiting automation script. Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid choice. Please enter a number between 1-13."
                ;;
        esac
        
        echo -e "\nPress Enter to continue..."
        read
    done
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi