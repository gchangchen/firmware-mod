#!/bin/bash

DIR="$1"
NEXT_PARAM=""

if [ "$DIR" == "" ] || [ "$DIR" == "-nopad" ] || [ "$DIR" == "-min" ]; then
	DIR="fmk"
	NEXT_PARAM="$1"
else
	NEXT_PARAM="$2"
fi


# Import shared settings. $DIR MUST be defined prior to this!
IMAGE_PARTS="$DIR/image_parts"
LOGS="$DIR/logs"
CONFLOG="$LOGS/config.log"
BINLOG="$LOGS/binwalk.log"
ROOTFS="$DIR/rootfs"
FSIMG="$IMAGE_PARTS/rootfs.img"
HEADER_IMAGE="$IMAGE_PARTS/header.img"
FOOTER_IMAGE="$IMAGE_PARTS/footer.img"
FWOUT="$DIR/new-firmware.bin"
BINWALK="./bin/binwalk"
UNSQUASHFS="./bin/unsquashfs"
MKSQUASHFS="./bin/mksquashfs"
CRCALC="./bin/crcalc"

eval $(cat $CONFLOG)
FSOUT="$DIR/new-filesystem.$FS_TYPE"

if [ ! -d "$DIR" ]
then
	echo -e "Usage: $0 [build directory] [-nopad]\n"
	exit 1
fi

echo "Building new $FS_TYPE file system..."

# Build the appropriate file system
case $FS_TYPE in
	"squashfs")
		# Increasing the block size minimizes the resulting image size (larger dictionary). Max block size of 1MB.
		if [ "$NEXT_PARAM" == "-min" ];	then
			echo "Blocksize override (-min). Original used $((FS_BLOCKSIZE/1024))KB blocks. New firmware uses 1MB blocks."
			FS_BLOCKSIZE="$((1024*1024))"
		fi

		# if blocksize var exists, then add '-b' parameter
		if [ "$FS_BLOCKSIZE" != "" ]; then
			BS="-b $FS_BLOCKSIZE"
			HR_BLOCKSIZE="$(($FS_BLOCKSIZE/1024))"
			echo "Squahfs block size is $HR_BLOCKSIZE Kb"
		fi

		$MKSQUASHFS "$ROOTFS" "$FSOUT" -comp xz -nopad  -root-owned -noappend -Xbcj arm
		;;
#	"cramfs")
#		$SUDO $MKFS "$ROOTFS" "$FSOUT"
#		if [ "$ENDIANESS" == "-be" ]
#		then
#			mv "$FSOUT" "$FSOUT.le"
#			./src/cramfsswap/cramfsswap "$FSOUT.le" "$FSOUT"
#			rm -f "$FSOUT.le"
#		fi
#		;;
	*)
		echo "Unsupported file system '$FS_TYPE'!"
		;;
esac

if [ ! -e $FSOUT ]
then
	echo "Failed to create new file system! Quitting..."
	exit 1
fi

# Append the new file system to the first part of the original firmware file
cp $HEADER_IMAGE $FWOUT
cat $FSOUT >> $FWOUT

# Calculate and create any filler bytes required between the end of the file system and the footer / EOF.
CUR_SIZE=$(ls -l $FWOUT | awk '{print $5}')
((FILLER_SIZE=$FW_SIZE-$CUR_SIZE-$FOOTER_SIZE))

if [ "$FILLER_SIZE" -lt 0 ]
then
	echo "ERROR: New firmware image will be larger than original image!"
	echo "       Building firmware images larger than the original can brick your device!"
	echo "       Try removing unnecessary files from the file system to decrease total image size."
	echo "       Refusing to create new firmware image."
	echo ""
	echo "       Original file size: $FW_SIZE"
	echo "       Current file size:  $CUR_SIZE"
	echo ""
	echo "       Quitting..."
	rm -f "$FWOUT"
	exit 1
else
	if [ "$NEXT_PARAM" != "-nopad" ]; then
		echo "Remaining free bytes in firmware image: $FILLER_SIZE"
		perl -e "print \"\xFF\"x$FILLER_SIZE" >> "$FWOUT"
	else
		echo "Padding of firmware image disabled via -nopad"
	fi	
fi

# Append the footer to the new firmware image, if there is any footer
if [ "$FOOTER_SIZE" -gt "0" ]
then
	cat $FOOTER_IMAGE >> "$FWOUT"
fi

# Calculate new checksum values for the firmware header
$CRCALC "$FWOUT" "$BINLOG"

if [ $? -eq 0 ]
then
	echo -n "Finished! "
else
	echo -n "Firmware header not supported; firmware checksums may be incorrect. "
fi

echo "New firmware image has been saved to: $FWOUT"

