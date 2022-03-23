#!/bin/bash
set -o nounset  # Fail when access undefined variable
set -o errexit  # Exit when a command fails

# Cache folder for API requests
_KRCL_BROADCAST_CACHE_DIR="/tmp/krcl_broadcast_cache";
mkdir -p "${_KRCL_BROADCAST_CACHE_DIR}";

export TZ="America/Denver" 
_tmpdata=$(mktemp);

# @ TODO
# The timezones are screwed up...the broadcast data reports it's in UTC timezone and it is
# But the Playlist data reports UTC but *IT'S NOT UTC*. It's America/Denver, but claims Greenwich...
# This screws w/ all the date handling code...
# Need to normalize / fix the timezone data...

log() {
	echo "$@"
}

error() {
	echo "$@"
	exit 1
}

cleanup() {
	rm -f ${_tmpdata}.sql ${_tmpdata}.json;
}

trap cleanup EXIT

# Shows
_update_shows() {
	echo "Updating show data"
	urls=$(seq -s " " -f  "https://krcl-studio.creek.org/api/shows?page=%0.0f" 1 5)
	wget -q -O - $urls \
 	| jq -r '.data[] | "REPLACE INTO shows (show_id, title, name, updated_at) VALUES ( \(.id), \"\(.title)\", \"\(.name)\", \"\(.updated_at)\"); "' \
 	| sqlite3 db/krcl-playlist-data.sqlite3
}
#_update_shows

######
## Fetch broadcasts from api at https://krcl-studio.creek.org/api/broadcasts?page=...
## $1 date maximum age to fetch. Defaults to 2 weeks
######
#_oldest=$(echo "SELECT IFNULL( max(start), DATETIME('now', '-30 day') ) from broadcasts WHERE start < datetime('now', '-12 hour');" | sqlite3 "db/krcl-playlist-data.sqlite3" );
#t_oldest=$(TZ="America/Denver" date --date="${_oldest}" "+%s");
update_broadcasts() {
	_arg_maxdate=${1:-"2 weeks ago"};
	_ts_maxdate=$(TZ="America/Denver" date --date="${_arg_maxdate}" "+%s");
	_ts_last=$(TZ="America/Denver" date --date="Now" "+%s");
	_pg=0;
	_baseurl="https://krcl-studio.creek.org/api/broadcasts?page=";

	_sql='SELECT strftime("%s", start) FROM broadcasts WHERE start > DATE("now", "-14 day") AND tracks_processed=1 ORDER BY start DESC LIMIT 1;';
	_ts_last_success=$(echo "${_sql}" | sqlite3 db/krcl-playlist-data.sqlite3); 
	
	if [[ "${_ts_last_success}" -eq "" ]]; then
		_ts_last_success=$_ts_maxdate;
	fi
	
	if [ "${_ts_maxdate}" -lt "${_ts_last_success}" ]; then
		_ts_maxdate="${_ts_last_success}";
	fi 

	# Grab each page and process
	while [ "${_ts_last}" -gt "${_ts_maxdate}" ]; do
		_pg=$(( ${_pg}+1 ));
		_url="${_baseurl}${_pg}";

		log "Fetching broadcast page at $_url";
		log "Time to fetch (seconds):" $(( ${_ts_last} - ${_ts_maxdate} ));
	
		wget --user-agent="Firefox" -q -O "${_tmpdata}.json" "${_url}" || error "wget failed";
		
		_ts_last=$(cat "${_tmpdata}.json" | jq '[.data[].start | strptime("%Y-%m-%dT%H:%M:%S.000000Z") | mktime] | min');
		log "Oldest timestamp on page #${_pg}: ${_ts_last}";
		jq -r -f "update_broadcasts.jq" "${_tmpdata}.json" >> "${_tmpdata}.sql"; 
	done
	log "Updating broadcast data from ${_tmpdata}.sql"; 
	sqlite3 db/krcl-playlist-data.sqlite3 < "${_tmpdata}.sql";
}
update_broadcasts; 


######
# Fetch and update songs for a broadcast
# $1 int broadcast_id (Required)
######
fetch_broadcast_songs() {
	[[ $1 == ?(-)+([0-9]) ]] || error "fetch_broadcast_songs: broadcast_id must be numeric"
	_bid="$1";
	log "Fetch song data for broadcast ${_bid}";
	_json="${_KRCL_BROADCAST_CACHE_DIR}/broadcast-${_bid}.json";
	_url="https://krcl.studio.creek.org/api/broadcasts/${_bid}";

	
	if [ -e "${_json}" ]; then
		# Cache file already exists, use it	
		log "Cache hit: broadcast ${_bid} already saved at ${_json}";
	else 
		# Fetch the broadcast data
		log "Cache miss: fetching broadcast data from ${_url}";
		wget --user-agent "Firefox" -q -O "${_json}" "${_url}";
	fi

	jq -r -f update_playlists.jq "$_json" \
		| sed 's/\\"/""/g' \
		| sqlite3 db/krcl-playlist-data.sqlite3

	log "Updated ${_bid}";

	echo "UPDATE broadcasts SET tracks_processed=1 WHERE broadcast_id=${_bid}" \
		| sqlite3 db/krcl-playlist-data.sqlite3
}


########
## Grab track / song data for each broadcast with tracks_processed!=1
########
update_broadcast_songs() {
	_sql=$(cat << END_QUERY
		SELECT broadcast_id FROM broadcasts 
		WHERE 
			DATETIME(start) < DATETIME('now', '-12 hour') 
			AND tracks_processed != 1 ORDER BY start DESC
END_QUERY
);
	for _bid in $(echo "${_sql}" | sqlite3 db/krcl-playlist-data.sqlite3); do
		log "Update broadcast songs for broadcast #${_bid}";
		fetch_broadcast_songs "${_bid}";
	done
}
update_broadcast_songs

