#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: customize-win98-instance.sh <INSTANCE_INDEX> <OUTPUT_DIR>" >&2
  exit 1
fi

instance_index="$1"
output_dir="$2"

if ! [[ "$instance_index" =~ ^[0-8]$ ]]; then
  echo "INSTANCE_INDEX must be 0-8, got '$instance_index'" >&2
  exit 1
fi

computer_name="LOCO-0${instance_index}"
workgroup="LOCOLAND"
ip_address="192.168.10.$((10 + instance_index))"
subnet_mask="255.255.255.0"
gateway="${GUEST_GATEWAY:-192.168.10.$((200 + instance_index))}"
description="Lego Loco Instance ${instance_index}"

mkdir -p "$output_dir"

reg_file="$output_dir/LOCO-ID.REG"
bat_file="$output_dir/LOCO-ID.BAT"
lmhosts_file="$output_dir/LMHOSTS"
autorun_file="$output_dir/AUTORUN.INF"

cat > "$reg_file" <<EOF
REGEDIT4

[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\VxD\VNETSUP]
"ComputerName"="${computer_name}"
"Workgroup"="${workgroup}"
"Comment"="${description}"

[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Class\NetTrans\0000]
"IPAddress"="${ip_address}"
"IPMask"="${subnet_mask}"
"DefaultGateway"="${gateway}"
"EnableDHCP"="0"

[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Class\NetTrans\0001]
"IPAddress"="${ip_address}"
"IPMask"="${subnet_mask}"
"DefaultGateway"="${gateway}"
"EnableDHCP"="0"

[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\VxD\MSTCP]
"BcastNameQueryCount"="3"
"NameSrvQueryCount"="3"
"EnableDNS"="0"
"NameServer"=""
"NodeType"="8"
"EnableLMHOSTS"="1"
"LMHostFile"="C:\\\\WINDOWS\\\\LMHOSTS"
EOF

cat > "$bat_file" <<EOF
@ECHO OFF
IF EXIST C:\\WINDOWS\\LOCO-ID.OK GOTO DONE
SET LOCODRV=
IF EXIST A:\\LOCO-ID.REG SET LOCODRV=A:
IF EXIST B:\\LOCO-ID.REG SET LOCODRV=B:
IF EXIST D:\\LOCO-ID.REG SET LOCODRV=D:
IF EXIST E:\\LOCO-ID.REG SET LOCODRV=E:
IF EXIST F:\\LOCO-ID.REG SET LOCODRV=F:
IF EXIST G:\\LOCO-ID.REG SET LOCODRV=G:
IF EXIST H:\\LOCO-ID.REG SET LOCODRV=H:
IF "%LOCODRV%"=="" GOTO NOFILES
REGEDIT /S %LOCODRV%\\LOCO-ID.REG
IF EXIST %LOCODRV%\\LMHOSTS COPY %LOCODRV%\\LMHOSTS C:\\WINDOWS\\LMHOSTS
ECHO ComputerName=${computer_name} > C:\\WINDOWS\\LOCO-ID.TXT
ECHO IPAddress=${ip_address} >> C:\\WINDOWS\\LOCO-ID.TXT
ECHO Workgroup=${workgroup} >> C:\\WINDOWS\\LOCO-ID.TXT
ECHO Gateway=${gateway} >> C:\\WINDOWS\\LOCO-ID.TXT
ECHO OK > C:\\WINDOWS\\LOCO-ID.OK
GOTO DONE
:NOFILES
ECHO LOCO identity media not found > C:\\WINDOWS\\LOCO-ID.ERR
:DONE
EOF

cat > "$autorun_file" <<EOF
[autorun]
open=COMMAND.COM /C LOCO-ID.BAT
shell\\configure=&Configure Loco Identity
shell\\configure\\command=COMMAND.COM /C LOCO-ID.BAT
EOF

cat > "$lmhosts_file" <<EOF
# LMHOSTS - static NetBIOS name table for LOCOLAND
EOF

for peer_index in $(seq 0 8); do
  echo "192.168.10.$((10 + peer_index))    LOCO-0${peer_index}" >> "$lmhosts_file"
done

sed -i 's/$/\r/' "$reg_file" "$bat_file" "$lmhosts_file" "$autorun_file"
