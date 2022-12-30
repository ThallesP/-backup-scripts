#!/bin/bash

# Rclone upload script with optional Discord notification upon move completion (if something is moved)
#
# Recommended for use via cron
# For example: 0 */2 * * * /path/to/rclone-upload.sh >/var/log/rclone-upload.log 2>&1
# Place inside `crontab -e`
# -----------------------------------------------------------------------------

DISCORD_NAME_OVERRIDE=""
DISCORD_ICON_OVERRIDE=""
DISCORD_WEBHOOK_URL="https://eaeirmao"

# You can have multiple servers, just duplicate the following lines and change from server1 to server2
# For example:
# declare -A server2=(
#    [name]="app"
#    [sourceDIR]="/var/lib/app"
#    [destinationDIR]="remote:/backups/app/app-`date +%d-%B-%Y--%H:%M:%S`"
# )
declare -A server1=(
    [name]="rpmdb"
    [sourceDIR]="/var/lib/rpm"
    [destinationDIR]="remote:/backups/rpmdb/rpmdb-`date +%d-%B-%Y--%H:%M:%S`"
)

declare -n server

LOCK_FILE="$HOME/rclone-upload.lock"

# DO NOT EDIT BELOW THIS LINE UNLESS YOU KNOW WHAT YOU'RE DOING
# -----------------------------------------------------------------------------

trap 'rm -f $LOCK_FILE; exit 0' SIGINT SIGTERM
if [ -e "$LOCK_FILE" ]; then
    echo "$0 is already running."
    exit
fi
touch "$LOCK_FILE"

exit_script() {
 rm -f "$LOCK_FILE"
 trap - SIGINT SIGTERM
 exit
}

execute_backup() {
    rclone_command=$(
        tar --use-compress-program="pigz -k " -cf - "$1" |
            rclone rcat -v \
                --drive-chunk-size 512M \
                --fast-list \
                --use-json-log \
                --stats=9999m \
                "$2" 2>&1
    )
    # "--stats=9999m" mitigates early stats output
    # "2>&1" ensures error output when running via command line

    RCLONE_JSON="$(echo $rclone_command)"
    echo $RCLONE_JSON
    RCLONE_COMPLETE_MSG=$(jq -r .msg <<<"$RCLONE_JSON")
    RCLONE_SANITIZED=$(sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' <<<"$RCLONE_COMPLETE_MSG")
    RCLONE_TOTAL_BYTES_TRANSFERRED=$(jq -e .stats.totalBytes <<<"$RCLONE_JSON")

    RCLONE_ELAPSED_TIME=${RCLONE_SANITIZED##*Elapsed time:}
    RCLONE_TOTAL_HM_TRANSFERRED=$(numfmt --to=iec --format="%.3f" <<<"$RCLONE_TOTAL_BYTES_TRANSFERRED")
    RCLONE_ERRORS_COUNT=$(jq -e .stats.errors <<<"$RCLONE_JSON")
    if [ "$RCLONE_ERRORS_COUNT" -eq 0 ]; then
        RCLONE_HAD_ERRORS="gg nao teve"
    else
	send_error_notification "$3"
	exit_script
    fi

    send_notification "$RCLONE_HAD_ERRORS" "$RCLONE_TOTAL_HM_TRANSFERRED" "$RCLONE_ELAPSED_TIME" "$3"
}

send_error_notification() {

    notification_data='{
        "username": "'"$DISCORD_NAME_OVERRIDE"'",
        "avatar_url": "'"$DISCORD_ICON_OVERRIDE"'",
        "embeds": [
          {
            "title": "'" :x: CAPOTEI O CORSA NO BACKUP DO $1"'",
            "color": 16711680,
	    "description": "The corsa has been capoted.\nveja o motivo do incidente em /var/log/rclone-upload.log",
	    "image": {
	      "url": "https://imageproxy.ifunny.co/crop:x-20,resize:640x,quality:90x75/images/794323e990e45b8a3da12758d5920f7a0db40c467574a42731aec292e5940387_1.jpg"
	    }
          }
	]
      }'
    echo $notification_data
    curl -H "Content-Type: application/json" -d "$notification_data" $DISCORD_WEBHOOK_URL
}

send_notification() {

    notification_data='{
        "username": "'"$DISCORD_NAME_OVERRIDE"'",
        "avatar_url": "'"$DISCORD_ICON_OVERRIDE"'",
        "content": null,
        "embeds": [
          {
            "title": "'"✅ Backup $4 finalizado!"'",
            "color": 65280,
            "fields": [
              {
                "name": "Concluido em:",
                "value": "'"$3"'"
              },
	      {
	       "name": "Tamanho do Backup:",
	       "value": "'"$2"'"
	      },
	      {
	       "name": "Teve algum erro?",
	       "value": "'"$1"'"
	      }
            ],
            "thumbnail": {
              "url": null
            }
          }
        ]
      }'
    echo $notification_data
    curl -H "Content-Type: application/json" -d "$notification_data" $DISCORD_WEBHOOK_URL
}

for server in "${!server@}"; do
    SERVER_NAME="${server[name]}"
    SOURCE_DIR="${server[sourceDIR]}"
    DESTINATION_DIR="${server[destinationDIR]}"
    execute_backup "$SOURCE_DIR" "$DESTINATION_DIR" "$SERVER_NAME"
done
echo "finished"

exit_script
