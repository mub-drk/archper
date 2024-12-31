#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Identify the USB device that booted the system
BOOT_DEVICE=$(lsblk -o NAME,MOUNTPOINT | grep '/run/archiso/bootmnt' | awk '{print $1}')
if [ -z "$BOOT_DEVICE" ]; then
  echo "Could not identify the boot device. Ensure you are booted from the USB."
  exit 1
fi

BOOT_DEVICE="/dev/${BOOT_DEVICE::-1}"  # Remove partition number

# Confirm action with the user
echo "The installation will overwrite the boot device: $BOOT_DEVICE"
read -p "Are you sure you want to continue? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Installation aborted."
  exit 1
fi

# Unmount all partitions on the boot device
echo "Unmounting partitions on $BOOT_DEVICE..."
umount -R /mnt 2>/dev/null || true
umount ${BOOT_DEVICE}* 2>/dev/null || true

# Partition the USB
echo "Partitioning $BOOT_DEVICE..."
parted -s "$BOOT_DEVICE" mklabel gpt
parted -s "$BOOT_DEVICE" mkpart ESP fat32 1MiB 513MiB
parted -s "$BOOT_DEVICE" set 1 esp on
parted -s "$BOOT_DEVICE" mkpart primary ext4 513MiB 100%

# Format the partitions
echo "Formatting partitions..."
mkfs.fat -F32 "${BOOT_DEVICE}1"
mkfs.ext4 "${BOOT_DEVICE}2"

# Mount the partitions
echo "Mounting partitions..."
mount "${BOOT_DEVICE}2" /mnt
mkdir -p /mnt/boot
mount "${BOOT_DEVICE}1" /mnt/boot

# Install base Arch Linux system
echo "Installing base system..."
pacstrap /mnt base linux linux-firmware

# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Configure the system
echo "Configuring the system..."
arch-chroot /mnt /bin/bash <<EOF
# Set timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

# Set locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "arch-usb" > /etc/hostname

# Set root password
echo "root:password" | chpasswd

# Install bootloader
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable
grub-mkconfig -o /boot/grub/grub.cfg
EOF

# Unmount and finish
echo "Unmounting and finishing installation..."
umount -R /mnt

echo "Arch Linux has been successfully installed with persistence on $BOOT_DEVICE!"
echo "Reboot now and boot from the USB to use your new system."
