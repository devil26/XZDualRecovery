#!/sbin/busybox sh
#
# Dual Recovery for the Xperia Z, ZL, Tablet Z, Z Ultra and Z1!
#
# Author:
#   [NUT]
#
# - Thanks go to DooMLoRD for the keycodes and a working example!
# - My gratitude also goes out to Androxyde for his sometimes briliant
#   ideas to simplify things while writing the scripts!
#
###########################################################################

set +x
_PATH="$PATH"
export PATH="/system/xbin:/system/bin:/sbin"

# Defining constants, from commandline
DRPATH="$1"
LOGFILE="$2"
LOG="${DRPATH}/${LOGFILE}"

# Kickstarting log
DATETIME=`date +"%d-%m-%Y %H:%M:%S"`
echo "START Dual Recovery at ${DATETIME}: STAGE 2." > ${LOG}

# Z setup
#BOOTREC_CACHE_NODE="/dev/block/mmcblk0p25 b 179 25"
#BOOTREC_CACHE="/dev/block/mmcblk0p25"
BOOTREC_EXTERNAL_SDCARD_NODE="/dev/block/mmcblk1p1 b 179 32"
BOOTREC_EXTERNAL_SDCARD="/dev/block/mmcblk1p1"
BOOTREC_LED_RED="/sys/class/leds/$(/system/xbin/busybox ls -1 /sys/class/leds|/system/xbin/busybox grep \"red\|LED1_R\")/brightness"
BOOTREC_LED_GREEN="/sys/class/leds/$(/system/xbin/busybox ls -1 /sys/class/leds|/system/xbin/busybox grep \"green\|LED1_G\")/brightness"
BOOTREC_LED_BLUE="/sys/class/leds/$(/system/xbin/busybox ls -1 /sys/class/leds|/system/xbin/busybox grep \"blue\|LED1_B\")/brightness"

# Defining functions
ECHOL(){
  _TIME=`busybox date +"%H:%M:%S"`
  echo "$_TIME: $*" >> ${LOG}
  return 0
}
EXECL(){
  _TIME=`busybox date +"%H:%M:%S"`
  echo "$_TIME: $*" >> ${LOG}
  $* 2>&1 >> ${LOG}
  _RET=$?
  echo "$_TIME: RET=$_RET" >> ${LOG}
  return ${_RET}
}
SETLED() {
        if [ "$1" = "on" ]; then

                ECHOL "Turn on LED R: $2 G: $3 B: $4"
                echo "$2" > ${BOOTREC_LED_RED}
                echo "$3" > ${BOOTREC_LED_GREEN}
                echo "$4" > ${BOOTREC_LED_BLUE}

        else

                ECHOL "Turn off LED"
                echo "0" > ${BOOTREC_LED_RED}
                echo "0" > ${BOOTREC_LED_GREEN}
                echo "0" > ${BOOTREC_LED_BLUE}

        fi
}
DRGETPROP() {

	# Get the property from getprop
	VAR=`$*`
	PROP=`/system/bin/getprop $*`

	if [ "$PROP" = "" ]; then

		# If it's empty, see if what was requested was a XZDR.prop value!
		VAR=`grep "$*" ${DRPATH}/XZDR.prop | awk -F'=' '{ print $1 }'`
		PROP=`grep "$*" ${DRPATH}/XZDR.prop | awk -F'=' '{ print $NF }'`

	fi
	if [ "$VAR" = "" -a "$PROP" = "" ]; then

		# If it still is empty, try to get it from the build.prop
		VAR=`grep "$*" /system/build.prop | awk -F'=' '{ print $1 }'`
		PROP=`grep "$*" /system/build.prop | awk -F'=' '{ print $NF }'`

	fi

	if [ "$VAR" != "" ]; then
		echo $PROP
	else
		echo "false"
	fi

}
DRSETPROP() {

	# We want to set this only if the XZDR.prop file exists...
	if [ ! -f "${DRPATH}/XZDR.prop" ]; then
		return 0
	fi

	PROP=$(DRGETPROP $1)

	if [ "$PROP" != "false" ]; then
		sed -i 's|'$1'=[^ ]*|'$1'='$2'|' ${DRPATH}/XZDR.prop
	else
		echo "$1=$2" >> ${DRPATH}/XZDR.prop
	fi
	return 0

}

ECHOL "Checking device model..."
MODEL=$(DRGETPROP ro.product.model)
VERSION=$(DRGETPROP ro.build.id)
PHNAME=$(DRGETPROP ro.semc.product.name)
EVENTNODE=$(DRGETPROP dr.gpiokeys.node)

ECHOL "Model found: $MODEL ($PHNAME - $VERSION)"

EXECL mount -o remount,rw rootfs /

RECOVERYBOOT="false"
KEYCHECK=""

if [ "$(grep 'warmboot=0x77665502' /proc/cmdline | wc -l)" = "1" ]; then

	ECHOL "Reboot 'recovery' trigger found."
	RECOVERYBOOT="true"

elif [ -f "/cache/recovery/boot" -o -f "${DRPATH}/boot" ]; then

	ECHOL "Recovery 'boot file' trigger found."
	RECOVERYBOOT="true"

else

	ECHOL "DR Keycheck..."
	cat ${EVENTNODE} > /dev/keycheck &

	# Vibrate to alert user to make a choice
	ECHOL "Trigger vibrator"
	echo 150 > /sys/class/timed_output/vibrator/enable
	usleep 300000
	echo 150 > /sys/class/timed_output/vibrator/enable

	# Turn on green LED as a visual cue
	SETLED on 0 255 0

	EXECL sleep 3

	hexdump < /dev/keycheck > /dev/keycheckout

	VOLUKEYCHECK=`cat /dev/keycheckout | grep '0001 0073' | wc -l`
	VOLDKEYCHECK=`cat /dev/keycheckout | grep '0001 0072' | wc -l`

	if [ "$VOLUKEYCHECK" != "0" ]; then
		ECHOL "Recorded VOL-UP on ${EVENTNODE}!"
		KEYCHECK="UP"
	elif [ "$VOLDKEYCHECK" != "0" ]; then
		ECHOL "Recorded VOL-DOWN on ${EVENTNODE}!"
		KEYCHECK="DOWN"
	elif [ "$VOLUKEYCHECK" != "0" -a "$VOLDKEYCHECK" != "0" ]; then
		ECHOL "Recorded BOTH VOL-UP & VOL-DOWN on ${EVENTNODE}! Making the choice to go to the UP target..."
		KEYCHECK="UP"
	fi

	EXECL killall cat

	EXECL rm -f /dev/keycheck
	EXECL rm -f /dev/keycheckout

	EXECL mount -o remount,ro rootfs /

	if [ "$KEYCHECK" != "" ]; then

		ECHOL "Recovery 'volume button' trigger found."
		RECOVERYBOOT="true"

	fi

fi

if [ "$RECOVERYBOOT" = "true" ]; then

	# Recovery boot mode notification
	SETLED on 255 0 255

	if [ -f "/cache/recovery/boot" ]; then
		EXECL rm -f /cache/recovery/boot
	fi

	cd /

	EXECL mount -o remount,rw rootfs /

	# reboot recovery trigger or boot file found, no keys pressed: read what recovery to use
	if [ "$KEYCHECK" = "" ]; then
		RECLOAD="$(DRGETPROP dr.recovery.boot)"
		RECLOG="Booting to ${RECLOAD}..."
	fi

  	# Prepare PhilZ recovery - by button press
	if [ -f "/system/bin/recovery.philz.cpio.lzma" -a "$KEYCHECK" = "UP" ]; then
		RECLOAD="philz"
		RECLOG="Booting recovery by keypress, booting to PhilZ Touch..."
	fi

	# Prepare TWRP recovery - by button press
	if [ -f "/system/bin/recovery.twrp.cpio.lzma" -a "$KEYCHECK" = "DOWN" ]; then
		RECLOAD="twrp"
		RECLOG="Booting recovery by keypress, booting to TWRP..."
	fi

	# Copy, unpack and prepare loading the recovery.
	DRSETPROP dr.recovery.boot ${RECLOAD}
	EXECL cp /system/bin/recovery.${RECLOAD}.cpio.lzma /sbin/
	EXECL lzma -d /sbin/recovery.${RECLOAD}.cpio.lzma
	RECOVERY="/sbin/recovery.${RECLOAD}.cpio"

	# Boot the recovery, if the file exists
	if [ -f "${RECOVERY}" ]; then

		# Record choice in log
		ECHOL "${RECLOG}"

		# Stop init services.
		ECHOL "Stop init services..."
		for SVCRUNNING in $(getprop | grep -E '^\[init\.svc\..*\]: \[running\]'); do
			SVCNAME=$(expr ${SVCRUNNING} : '\[init\.svc\.\(.*\)\]:.*')
			if [ "${SVCNAME}" != "" ]; then
				EXECL stop ${SVCNAME}
				if [ -f "/system/bin/${SVCNAME}" ]; then
					EXECL pkill -f /system/bin/${SVCNAME}
				fi
			fi
		done

		for LOCKINGPID in `lsof | awk '{print $1" "$2}' | grep -E "/bin|/system|/data|/cache" | awk '{print $1}'`; do
			BINARY=$(ps | grep " $LOCKINGPID " | grep -v "grep" | awk '{print $5}')
			ECHOL "File ${BINARY} is locking a critical partition running as PID ${LOCKINGPID}, killing it now!"
			EXECL kill -9 $LOCKINGPID
		done

		# umount partitions, stripping the ramdisk to bare metal
		ECHOL "Umount partitions and then executing init..."
		EXECL umount -l /acct
		EXECL umount -l /dev/cpuctl
		EXECL umount -l /dev/pts
		EXECL umount -l /mnt/int_storage
		EXECL umount -l /mnt/asec
		EXECL umount -l /mnt/obb
		EXECL umount -l /mnt/qcks
		EXECL umount -l /mnt/idd	# Appslog
		EXECL umount -l /data/idd	# Appslog
		EXECL umount -l /data		# Userdata
		EXECL umount -l /lta-label	# LTALabel

		# Create recovery directory to create a new root in.
		EXECL mkdir /recovery
		EXECL cd /recovery

		# extract recovery
		ECHOL "Extracting recovery..."
		EXECL cpio -i -u < /sbin/recovery.${RECLOAD}.cpio

		EXECL pwd
		EXECL ls -la

		# Turn off LED
		SETLED off

		# From here on, the log dies, as these are the locations we log to!
		# Ending log
		DATETIME=`date +"%d-%m-%Y %H:%M:%S"`
		ECHOL "STOP Dual Recovery at ${DATETIME}: Executing recovery init, have fun!"

		umount -l /storage/sdcard1	# SDCard1
		umount -l /cache		# Cache
#		umount -l /proc
#		umount -l /sys

		# AS OF HERE NO MORE BUSYBOX SYMLINKS IN $PATH!!!!

		export PATH="/sbin"
		busybox umount -l /system	# System

		# exec
		busybox chroot /recovery /init

	else

		EXECL mount -o remount,ro rootfs /

		ECHOL "The recovery file does not exist, exitting with a visual warning!"
		SETLED on 255 0 0

		sleep 2

	fi

fi

# Turn off LED
SETLED off

# Check and prepare for stock ramdisk
STOCKRAMDISK=""
PACKED=""
INSECUREBOOT=""
if [ -f "$(DRGETPROP dr.ramdisk.path)" ] && [ "$(DRGETPROP dr.ramdisk.boot)" = "true" -o -f "/cache/ramdisk" ]; then

	if [ -f "/cache/ramdisk" ]; then
		EXECL rm -f /cache/ramdisk
	fi

	STOCKRAMDISK=$(DRGETPROP dr.ramdisk.path)
	PACKED=$(basename $STOCKRAMDISK | awk -F . '{print $NF}')
	INSECUREBOOT="true"

fi

if [ -f "$(DRGETPROP dr.ramdisk.path)" -a "$(DRGETPROP dr.ramdisk.boot)" = "power" ]; then

	POWERNODE=$(DRGETPROP dr.pwrkey.node)
	ECHOL "Power keycheck..."
	EXECL mount -o remount,rw rootfs /

	cat ${POWERNODE} > /dev/keycheck &

	# Vibrate to alert user to make a choice
	ECHOL "Trigger vibrator"
	echo 150 > /sys/class/timed_output/vibrator/enable
	usleep 300000
	echo 150 > /sys/class/timed_output/vibrator/enable

	# Turn on amber LED as a visual cue
	SETLED on 255 255 0

	EXECL sleep 3

	KEYCHECK=""

	hexdump < /dev/keycheck > /dev/keycheckout

	SETLED off

	POWERKEYCHECK=`cat /dev/keycheckout | wc -l`

	if [ "$POWERKEYCHECK" != "0" ]; then
		ECHOL "Power button pressed, will attempt booting insecure ramdisk!"
		STOCKRAMDISK=$(DRGETPROP dr.ramdisk.path)
		PACKED=$(basename $STOCKRAMDISK | awk -F . '{print $NF}')
		INSECUREBOOT="true"
	fi

	EXECL killall cat

	EXECL rm -f /dev/keycheck
	EXECL rm -f /dev/keycheckout

	EXECL mount -o remount,ro rootfs /

fi

if [ "$PACKED" != "" -a "$PACKED" != "lzma" -a "$PACKED" != "cpio" -a "$PACKED" != "tar" ]; then

	ECHOL "Unknown archive type, use only cpio, cpio.lzma and tar archives!"
	STOCKRAMDISK=""

fi

# If the ramdisk is not present or if the setting in the XZDR.prop
# file has been set to disabled, we do a regular boot.
if [ "$STOCKRAMDISK" != "" -a "$INSECUREBOOT" != "" ]; then

	EXECL mount -o remount,rw rootfs /

	ECHOL "Known archive type, will copy it to /sbin now"
	EXECL cp $STOCKRAMDISK /sbin/
	STOCKRAMDISK="/sbin/$(basename $STOCKRAMDISK)"

	ECHOL "Insecure ramdisk boot..."

	cd /

	# extract replacement ramdisk
	ECHOL "Extracting ramdisk..."
	if [ "$PACKED" = "tar" ]; then
		tar xf $STOCKRAMDISK
	elif [ "$PACKED" = "cpio" ]; then
		cpio -i -u < $STOCKRAMDISK
	else
		lzcat $STOCKRAMDISK | cpio -i -u
	fi

	# Ending log
	DATETIME=`date +"%d-%m-%Y %H:%M:%S"`
	ECHOL "STOP Dual Recovery at ${DATETIME}: Executing insecure ramdisk init, have fun!"

	# exec
	exec /init

else

	# init.d support
	if [ "$(DRGETPROP dr.initd.active)" = "true" ]; then

		ECHOL "Init.d folder found and execution is enabled!"
		ECHOL "It will run the following scripts:"
		run-parts -t /system/etc/init.d 2>&1 >> ${LOG}
		ECHOL "Executing them in the background now."
		nohup run-parts /system/etc/init.d &

	else

		ECHOL "Init.d execution is disabled."
		ECHOL "To enable it, set dr.initd.active to true in XZDR.prop!"

	fi

	ECHOL "Starting the rickiller to the background..."
	nohup /system/bin/rickiller.sh &

	EXECL mount -o remount,ro rootfs /
	EXECL mount -o remount,ro /system

	ECHOL "Return to normal boot mode..."

	# Ending log
	DATETIME=`busybox date +"%d-%m-%Y %H:%M:%S"`
	echo "STOP Dual Recovery at ${DATETIME}: STAGE 2." >> ${LOG}

	# Unmount SDCard1
	umount -f /storage/sdcard1

	# Return path variable to default
	export PATH="${_PATH}"

	# Continue booting
	exec /system/bin/chargemon.stock

fi
