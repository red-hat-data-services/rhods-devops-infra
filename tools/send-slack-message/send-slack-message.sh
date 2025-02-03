
#
CHANNEL="C07RGA06207"
MESSAGES=()
FILES=()
THREAD_ID=
VERBOSE=
STACK=()

function help {
cat <<EOF
./send-slack-message.sh [-v] [-h] [-c <channel>] [-t <thread>] [ <message> | -m <message> | -f <file_path> ]...
  SLACK_TOKEN - Required environment variable with the value of a Slack App OAuth token. 
  -c <channel>, --channel <channel>
    A slack channel identifier. Your Slack App must be added as a member to this channel. Will default to rhoai-konflux-poc-notifications channel.
  -t <thread>, --thread <thread>
    (optional) A slack message thread id. Use this to add messages as a reply to an existing message.
  <message>, -m <message>, --message <message> 
    Message to send. If multiple are specified, they will appear as replies to the first message.
  -f <file_path>, --file <file_path> 
    A file to upload. If specified after a message, it will appear as a reply to the message prior.
  -v, --verbose
    Show status messages as each payload is sent
  -h, --help
    Show this help file
EOF
}

while [ "$#" -gt 0 ]; do
  key="$1"
  case $key in 
    --help | -h)
      help
      exit
      ;;
    --file | -f)
      FILES+=("$2")
      STACK+=("file")
      shift 2
      ;;
    --channel | -c)
      CHANNEL="$2"
      if [ -z "$CHANNEL" ]; then
        echo "please specify a slack channel"
        help
        exit 1
      fi
      shift 2
      ;;
    --thread | -t)
      THREAD_ID="$2"
      if [ -z "$THREAD_ID" ]; then
        echo "-t, --thread flag requires a thread ID after it"
      fi
      shift 2
      ;; 
    --message | -m)
      MESSAGES+=("$2")
      STACK+=("message")
      shift 2
      ;;
    --verbose | -v)
      VERBOSE=true
      shift
      ;;
    -* | --*)
      echo "unrecognized argument $1"
      help
      exit 1
      ;;
    *)
      MESSAGES+=("$1") 
      STACK+=("message")
      shift
      ;;
  esac
done


function log () {
    if [[ "$VERBOSE" = "true" ]]; then
        echo "$@"
    fi
}

function slack_post {
  curl -s -X POST -H "Authorization: Bearer $SLACK_TOKEN" "$@" 
}
function slack_post_json {
  slack_post -H 'Content-type: application/json' "$@" 
}

function send_slack_message {
  msg="$1"
  thread="$2"
  payload=$(jq -n --arg C "$CHANNEL" --arg M "$msg" '{channel: $C, text: $M, mrkdwn: "true"}')
  if [ -n "$thread" ]; then
    payload=$(echo "$payload" | jq --arg T "$thread" '.thread_ts = $T')
  fi
  response_json=$(slack_post_json --data "$payload" https://slack.com/api/chat.postMessage)
  echo "$response_json" | jq -r '.ts'
}

function send_slack_file {
  file_path=$1
  thread=$2
  file_name=$(basename "$1")
  file_size=$(wc -c "$file_path" | awk '{print $1}') 

  # initial request to get an upload URL
  upload_url_response=$(slack_post --data-urlencode "filename=$file_name" --data-urlencode "length=$file_size"  https://slack.com/api/files.getUploadURLExternal)

  # log "upload request response: $upload_url_response"

  upload_url=$(jq -n -r --argjson X "$upload_url_response" '$X | .upload_url')
  
  # post of the file to the upload url
  post_response=$(curl -s -X POST -F filename="@$file_path" "$upload_url")
 
  # log "post response: $post_response"
 
  # final request to map the uploaded file to a channel message 
  final_payload=$(jq -n --arg C "$CHANNEL" --argjson X "$upload_url_response" '$X | {files:[{id:.file_id}],initial_comment:"", channel_id:$C}')

  # attach to an existing message if $thread is defined
  if [ -n "$thread" ]; then
    final_payload=$(echo "$final_payload" | jq --arg T "$thread" '.thread_ts = $T')
  fi

  final_response=$(slack_post_json --data "$final_payload"   https://slack.com/api/files.completeUploadExternal)
  log "final response: $final_response"
  
}

file_index=0
message_index=0
first_message=true
for type in "${STACK[@]}"; do
  if [ "$first_message" = true -a "$type" = "file" ]; then
    echo "warning - if a file is specified first, then subsequent messages will not appear as replies due to limitations in slack api"
  fi
  if [ "$type" = "message" ]; then
    log "sending message to thread id: $THREAD_ID" 
    message=${MESSAGES[$message_index]}
    NEW_THREAD_ID=$(send_slack_message "$message" "$THREAD_ID")
    log "Message sent"
    message_index=$(( $message_index + 1 ))
  else
    log "sending file to thread id: $THREAD_ID"
    file_path=${FILES[$file_index]}
    send_slack_file "$file_path" "$THREAD_ID"
    log "File sent"
    file_index=$(( $file_index + 1 ))
    # this helps keep the order of the messages correct 
    sleep 1
  fi
  if [ "$first_message" = true -o -z "$THREAD_ID" ]; then
    log "Setting new thread id: $NEW_THREAD_ID"
    THREAD_ID="$NEW_THREAD_ID"
  fi
  first_message=false
done


