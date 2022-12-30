#!/bin/bash

DISCORD_NAME_OVERRIDE=rm -rf
DISCORD_ICON_OVERRIDE=
DISCORD_WEBHOOK_URL=https://eaeirmao

LOCK_FILE="$HOME/cleanup-script.lock"

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

execute_cleanup() {
    rclone_cleanup_command=$(
        rclone delete \
            remote:/ \
            --use-json-log \
            --drive-use-trash=false \
            --min-age 4d \
            -v \
            2>&1
    )

    rclone_total_size_cleanup_command=$(
        rclone delete \
            remote:/ \
            --use-json-log \
            --drive-use-trash=false \
            --min-age 4d \
            -v --dry-run \
            2>&1
    )

    rclone_command_output="$(echo $rclone_cleanup_command)"
    rclone_total_size_output="$(echo $rclone_total_size_cleanup_command)"
    total_deleted_files_size=0

    while IFS= read -r line; do
        total_deleted_files_size=$((total_deleted_files_size + line))
    done < <(jq -r .size <<<"$rclone_total_size_output")

    if [ "$total_deleted_files_size" -eq 0 ]; then
        total_deleted_files_human_readable="Nenhum"
    else
        total_deleted_files_human_readable=$(numfmt --to=iec --format="%.3f" <<<"$total_deleted_files_size")
    fi

    send_notification $total_deleted_files_human_readable

    echo "finished cleanup"
    exit_script
}

send_notification() {

    notification_data='{
        "username": "'"$DISCORD_NAME_OVERRIDE"'",
        "avatar_url": "'"$DISCORD_ICON_OVERRIDE"'",
        "content": null,
        "embeds": [
          {
            "title": "'" ⚠️ Backups antigos deletados"'",
            "color": 16776960,
            "fields": [
              {
               "name": "Espaço liberado:",
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

execute_cleanup
