#!/bin/bash
set -o nounset  # Fail when access undefined variable
set -o errexit  # Exit when a command fails

_search_days=14;
_search_shows="all";
_opt_nodelay=false;

cmdl=`getopt -o d:s:n --long days:,shows:,now -- "$@"`
eval set -- "$cmdl"
while true ; do
    case "$1" in
    	-n|--now)
			_opt_nodelay=true;
			shift
		;;
    	-d|--days)
			if [[ $2 =~ ^[0-9]+$ ]]; then
				_search_days=$2;
				shift 2;	
			else 
				exit 1
			fi
			;;
		-s|--shows)
			_search_shows=$2;
			shift 2;
			;;
		*) 
			break ;;			
	esac
done

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
	echo "$@" #> /dev/null
}

error() {
	echo "$@"
	exit 1
}

cleanup() {
	echo rm -f ${_tmpdata}.sql ${_tmpdata}.json;
}

trap cleanup EXIT

function ProgressBar {
    # Process data
    _progress=$( awk "{ printf \"%0.2f\", (${1}*100/${2}*100)/100 }" <<< '');
    _done=$( awk "{ printf \"%0.2f\", ${_progress}*4/10 }" <<< '' );
    _left=$( awk "{ printf \"%0.0f\", 40-${_done} }" <<< '' );
    _msg="${3}";

    # Build progressbar string lengths
    _done=$(printf "%${_done}s")
    _left=$(printf "%${_left}s")

    # Build progressbar strings and print the ProgressBar line
    /usr/bin/printf "\r${_msg} Progress : [${_done// /#}${_left// /-}] ${_progress}%%"
}

# Shows
_update_shows() {
	echo "Updating show data"
	urls=$(seq -s " " -f  "https://krcl-studio.creek.org/api/shows?page=%0.0f" 1 5)
	wget -q -O - $urls \
 	| jq -r '.data[] | "REPLACE INTO shows (show_id, title, name, updated_at) VALUES ( \(.id), \"\(.title)\", \"\(.name)\", \"\(.updated_at)\"); "' \
 	| sqlite3 db/krcl-playlist-data.sqlite3
}
_update_shows

######
## Fetch broadcasts from api at https://krcl-studio.creek.org/api/broadcasts?page=...
## $1 date maximum age to fetch. Defaults to 2 weeks
######
#_oldest=$(echo "SELECT IFNULL( max(start), DATETIME('now', '-30 day') ) from broadcasts WHERE start < datetime('now', '-12 hour');" | sqlite3 "db/krcl-playlist-data.sqlite3" );
#t_oldest=$(TZ="America/Denver" date --date="${_oldest}" "+%s");
update_broadcasts() {
#	_arg_maxdate=${1:-"2 weeks ago"};
	_arg_maxdate=${1:-"${_search_days} days ago"};
	_ts_maxdate=$(TZ="America/Denver" date --date="${_arg_maxdate}" "+%s");
	_ts_last=$(TZ="America/Denver" date --date="Now" "+%s");
	_pg=0;
	_baseurl="https://krcl-studio.creek.org/api/broadcasts?page=";

	_sql='SELECT strftime("%s", start) FROM broadcasts WHERE start < DATE("now", "-'$_search_days' day") AND tracks_processed=1 ORDER BY start DESC LIMIT 1;';
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
		log "Oldest timestamp on page #${_pg}: ${_ts_last} $(date --date=@${_ts_last})";
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
		echo
	else 
		# Fetch the broadcast data
		#log "Cache miss: fetching broadcast data from ${_url}";
		wget --user-agent "Firefox" -q -O "${_json}" "${_url}";
#		echo -ne "${_url}\n  out=${_json}\n";
	fi
#}
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
	_sql_delay_time="-12 hour";
	if [[ $_opt_nodelay == true ]]; then
		_sql_delay_time="-1 second";
	fi

	_sql=$(cat << END_QUERY
		SELECT :field FROM broadcasts 
		WHERE 
			DATETIME(start) < DATETIME('now', '${_sql_delay_time}') 
			AND tracks_processed != 1 ORDER BY start DESC
END_QUERY
);
	_total=$(echo "${_sql}" | sed 's/:field/count\(\*\)/g' | sqlite3 db/krcl-playlist-data.sqlite3);
	_count=0; 
	echo
	echo "Updating updating broadcast songs";
	bids=();
	_ariaconf=$(mktemp);

	for _bid in $(echo "${_sql}" | sed 's/:field/broadcast_id/g' | sqlite3 db/krcl-playlist-data.sqlite3); do
		bids+=($_bid);
		_count=$(( _count+1 ));
		#ProgressBar $_count $_total "\rUpdating broadcast(#${_bid}) songs #${_count} of ${_total}"
		#log "Update broadcast songs for broadcast #${_bid}";
		#fetch_broadcast_songs "${_bid}";
		#echo -ne ""
		#${_KRCL_BROADCAST_CACHE_DIR}
		
		_file="broadcast-${_bid}.json";		
		if [ -e "${_KRCL_BROADCAST_CACHE_DIR}/${_file}" ]; then
			log "aria2 cache hit: ${_KRCL_BROADCAST_CACHE_DIR}/${_file} ";
		else 
			_url="https://krcl.studio.creek.org/api/broadcasts/${_bid}";
			echo -ne "${_url}\n  dir=${_KRCL_BROADCAST_CACHE_DIR}\n  out=${_file}\n" | tee -a ${_ariaconf};
		fi
	done

	echo "Saved to aria config file at ${_ariaconf}";
	echo "Downloading ${_count} broadcasts using aria2";

	aria2c -i "${_ariaconf}";

	#IFS=" \n";
	for b in "${bids[@]}"; do
		echo "fetch_broadcast_songs ${b}";
		fetch_broadcast_songs "${b}";
	done	

	#	exit 1;
	echo
}
update_broadcast_songs

