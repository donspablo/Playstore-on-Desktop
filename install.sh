#!/bin/bash

sudo apt update && sudo apt install snapd wget curl lzip tar unzip squashfs-tools -y && sleep 10
sudo snap install --devmode --edge anbox && sleep 5

set -e

ANBOX=$(which anbox)

SNAP_TOP=""
if ( [ -d '/var/snap' ] || [ -d '/snap' ] ) && \
	( [ ${ANBOX} = "/snap/bin/anbox" ] || [ ${ANBOX} == /var/lib/snapd/snap/bin/anbox ] );then
	if [ -d '/snap' ];then
		SNAP_TOP=/snap
	else
		SNAP_TOP=/var/lib/snapd/snap
	fi
	COMBINEDDIR="/var/snap/anbox/common/combined-rootfs"
	OVERLAYDIR="/var/snap/anbox/common/rootfs-overlay"
	WITH_SNAP=true
else
	COMBINEDDIR="/var/lib/anbox/combined-rootfs"
	OVERLAYDIR="/var/lib/anbox/rootfs-overlay"
	WITH_SNAP=false
fi

if [ ! -d "$COMBINEDDIR" ]; then
  	if $WITH_SNAP;then
		sudo snap set anbox rootfs-overlay.enable=true
		sudo snap restart anbox.container-manager
	else
		sudo cat >/etc/systemd/system/anbox-container-manager.service.d/override.conf<<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/anbox container-manager --daemon --privileged --data-path=/var/lib/anbox --use-rootfs-overlay
EOF
		sudo systemctl daemon-reload
		sudo systemctl restart anbox-container-manager.service
	fi

  sleep 20
fi

echo $OVERLAYDIR
if [ ! -d "$OVERLAYDIR" ]; then
    echo -e "Overlay no enabled ! Please check error messages!"
	exit 1
fi

sudo mkdir "/tmp/anbox" && cd "/tmp/anbox"

if [ -d "/tmp/anbox/squashfs-root" ]; then
  sudo rm -rf squashfs-root
fi

if $WITH_SNAP;then
	cp $SNAP_TOP/anbox/current/android.img .
else
	cp /var/lib/anbox/android.img .
fi
sudo unsquashfs android.img

if [ "$1" = "--layout" ]; then

	cd "/tmp/anbox"
	wget -q --show-progress -O anbox-keyboard.kcm -c https://phoenixnap.dl.sourceforge.net/project/androidx86rc2te/Generic_$2.kcm
	sudo cp anbox-keyboard.kcm "/tmp/anbox/squashfs-root/system/usr/keychars/anbox-keyboard.kcm"

	if [ ! -d "$OVERLAYDIR/system/usr/keychars/" ]; then
		sudo mkdir -p "$OVERLAYDIR/system/usr/keychars/"
		sudo cp "/tmp/anbox/squashfs-root/system/usr/keychars/anbox-keyboard.kcm" "$OVERLAYDIR/system/usr/keychars/anbox-keyboard.kcm"
	fi
fi

OPENGAPPS_RELEASEDATE="$(curl -s https://api.github.com/repos/opengapps/x86_64/releases/latest | grep tag_name | grep -o "\"[0-9][0-9]*\"" | grep -o "[0-9]*")"
OPENGAPPS_FILE="open_gapps-x86_64-7.1-pico-$OPENGAPPS_RELEASEDATE.zip"
OPENGAPPS_URL="https://sourceforge.net/projects/opengapps/files/x86_64/$OPENGAPPS_RELEASEDATE/$OPENGAPPS_FILE"

cd "/tmp/anbox"

while : ;do
 if [ ! -f ./$OPENGAPPS_FILE ]; then
	 wget -q --show-progress $OPENGAPPS_URL
 else
	 wget -q --show-progress -c $OPENGAPPS_URL
 fi
 [ $? = 0 ] && break
done

unzip -d opengapps ./$OPENGAPPS_FILE

cd ./opengapps/Core/
for filename in *.tar.lz
do
    tar --lzip -xvf ./$filename
done

cd "/tmp/anbox"
APPDIR="$OVERLAYDIR/system/priv-app"
if [ ! -d "$APPDIR" ]; then
	sudo mkdir -p "$APPDIR"
fi

sudo cp -r ./$(find opengapps -type d -name "PrebuiltGmsCore")					$APPDIR
sudo cp -r ./$(find opengapps -type d -name "GoogleLoginService")				$APPDIR
sudo cp -r ./$(find opengapps -type d -name "Phonesky")						$APPDIR
sudo cp -r ./$(find opengapps -type d -name "GoogleServicesFramework")			$APPDIR

cd "$APPDIR"
sudo chown -R 100000:100000 Phonesky GoogleLoginService GoogleServicesFramework PrebuiltGmsCore

cd "/tmp/anbox"
if [ ! -f ./houdini_y.sfs ]; then
  wget -O houdini_y.sfs -q --show-progress "http://dl.android-x86.org/houdini/7_y/houdini.sfs"
  mkdir -p houdini_y
  sudo unsquashfs -f -d ./houdini_y ./houdini_y.sfs
fi

LIBDIR="$OVERLAYDIR/system/lib"
if [ ! -d "$LIBDIR" ]; then
   sudo mkdir -p "$LIBDIR"
fi

sudo mkdir -p "$LIBDIR/arm"
sudo cp -r ./houdini_y/* "$LIBDIR/arm"
sudo chown -R 100000:100000 "$LIBDIR/arm"
sudo mv "$LIBDIR/arm/libhoudini.so" "$LIBDIR/libhoudini.so"

if [ ! -f ./houdini_z.sfs ]; then
  wget -O houdini_z.sfs -q --show-progress "http://dl.android-x86.org/houdini/7_z/houdini.sfs"
  mkdir -p houdini_z
  sudo unsquashfs -f -d ./houdini_z ./houdini_z.sfs
fi

LIBDIR64="$OVERLAYDIR/system/lib64"
if [ ! -d "$LIBDIR64" ]; then
   sudo mkdir -p "$LIBDIR64"
fi

sudo mkdir -p "$LIBDIR64/arm64"
sudo cp -r ./houdini_z/* "$LIBDIR64/arm64"
sudo chown -R 100000:100000 "$LIBDIR64/arm64"
sudo mv "$LIBDIR64/arm64/libhoudini.so" "$LIBDIR64/libhoudini.so"

# add houdini parser
BINFMT_DIR="/proc/sys/fs/binfmt_misc/register"
set +e
echo ':arm_exe:M::\x7f\x45\x4c\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28::/system/lib/arm/houdini:P' | sudo tee -a "$BINFMT_DIR"
echo ':arm_dyn:M::\x7f\x45\x4c\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\x28::/system/lib/arm/houdini:P' | sudo tee -a "$BINFMT_DIR"
echo ':arm64_exe:M::\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7::/system/lib64/arm64/houdini64:P' | sudo tee -a "$BINFMT_DIR"
echo ':arm64_dyn:M::\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\xb7::/system/lib64/arm64/houdini64:P' | sudo tee -a "$BINFMT_DIR"

set -e

C=$(cat <<-END
  <feature name="android.hardware.touchscreen" />\n
  <feature name="android.hardware.audio.output" />\n
  <feature name="android.hardware.camera" />\n
  <feature name="android.hardware.camera.any" />\n
  <feature name="android.hardware.location" />\n
  <feature name="android.hardware.location.gps" />\n
  <feature name="android.hardware.location.network" />\n
  <feature name="android.hardware.microphone" />\n
  <feature name="android.hardware.screen.portrait" />\n
  <feature name="android.hardware.screen.landscape" />\n
  <feature name="android.hardware.wifi" />\n
  <feature name="android.hardware.bluetooth" />"
END
)


C=$(echo $C | sed 's/\//\\\//g')
C=$(echo $C | sed 's/\"/\\\"/g')

if [ ! -d "$OVERLAYDIR/system/etc/permissions/" ]; then
  sudo mkdir -p "$OVERLAYDIR/system/etc/permissions/"
  sudo cp "/tmp/anbox/squashfs-root/system/etc/permissions/anbox.xml" "$OVERLAYDIR/system/etc/permissions/anbox.xml"
fi

sudo sed -i "/<\/permissions>/ s/.*/${C}\n&/" "$OVERLAYDIR/system/etc/permissions/anbox.xml"

sudo sed -i "/<unavailable-feature name=\"android.hardware.wifi\" \/>/d" "$OVERLAYDIR/system/etc/permissions/anbox.xml"
sudo sed -i "/<unavailable-feature name=\"android.hardware.bluetooth\" \/>/d" "$OVERLAYDIR/system/etc/permissions/anbox.xml"

if [ ! -x "$OVERLAYDIR/system/build.prop" ]; then
  sudo cp "/tmp/anbox/squashfs-root/system/build.prop" "$OVERLAYDIR/system/build.prop"
fi

if [ ! -x "$OVERLAYDIR/default.prop" ]; then
  sudo cp "/tmp/anbox/squashfs-root/default.prop" "$OVERLAYDIR/default.prop"
fi

sudo sed -i "/^ro.product.cpu.abilist=x86_64,x86/ s/$/,armeabi-v7a,armeabi,arm64-v8a/" "$OVERLAYDIR/system/build.prop"
sudo sed -i "/^ro.product.cpu.abilist32=x86/ s/$/,armeabi-v7a,armeabi/" "$OVERLAYDIR/system/build.prop"
sudo sed -i "/^ro.product.cpu.abilist64=x86_64/ s/$/,arm64-v8a/" "$OVERLAYDIR/system/build.prop"

echo "persist.sys.nativebridge=1" | sudo tee -a "$OVERLAYDIR/system/build.prop"
sudo sed -i '/ro.zygote=zygote64_32/a\ro.dalvik.vm.native.bridge=libhoudini.so' "$OVERLAYDIR/default.prop"

echo "ro.opengles.version=131072" | sudo tee -a "$OVERLAYDIR/system/build.prop"

if $WITH_SNAP;then
	sudo snap restart anbox.container-manager
else
	sudo systemctl restart anbox-container-manager.service
fi

sudo rm -rf "/tmp/anbox"

sleep 20

anbox launch --package=org.anbox.appmgr --component=org.anbox.appmgr.AppViewActivity
