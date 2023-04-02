#!/bin/bash 
#set -o nounset  # Fail when access undefined variable
#set -o errexit  # Exit when a command fails
#trap "sleep 30" ERR
export _KRCL_BITRATE=192;
export _KRCL_STREAM_CACHEDIR="cache/"
export _KRCL_BUFFER_SECS=15;

mkdir -p $_KRCL_STREAM_CACHEDIR
if [ -z "$TMUX" ]; then
	tmux new-session "./stream.sh"
	exit 0;
fi

_cvlc_cmd="vlc -I dummy -I ncurses --extraintf telnet --telnet-port 23456";
tmux split-pane -p 20 "$_cvlc_cmd"
tmux select-pane -t 0

_FZF_DEFAULT_OPTS='--bind "alt-up:execute(ncat_vlc volup)" --bind "alt-down:execute(ncat_vlc voldown)" --bind "alt-space:execute(ncat_vlc pause)"'

export _KRCL_LOGFILE=$(mktemp /tmp/krcl-logfile.XXXXX);

_CURL_PID=0;

broadcast_list() {
	_sql=$(cat << END_QUERY
	SELECT
		b.broadcast_id || "|" || sh.title || "|" || strftime("%Y-%m-%d %H:%M:%S", b.start)
	FROM broadcasts b 
		JOIN shows sh USING (show_id) 
	WHERE
		b.broadcast_id IN ( SELECT broadcast_id FROM playlists)
	ORDER BY start DESC;
END_QUERY
);

	export -f do_curl

	echo -e "\r\nbroadcast_list:\r\n$_sql" >> $_KRCL_LOGFILE;

	echo "$_sql" | sqlite3 -separator "|" db/krcl-playlist-data.sqlite3 \
	| column -s '|' -c 3 -t \
	| fzf -d "|" --reverse \
		--bind "alt-up:execute(ncat_vlc volup)" --bind "alt-down:execute(ncat_vlc voldown)" --bind "ctrl-space:execute(ncat_vlc pause)" --bind "alt-left:execute(ncat_vlc 'seek -5')" --bind "alt-right:execute(ncat_vlc 'seek +5')" \
		--bind "shift-down:half-page-down" --bind "shift-up:half-page-up" \
		--bind "pgdn:preview-half-page-down" --bind "pgup:preview-half-page-up" \
		--bind "esc:execute(tmux kill-session)" \
		--bind "esc:abort" \
		--preview "preview_playlist {1..7}" \
		--bind "enter:execute(show_playlist {1..7})" \
		--bind "double-click:execute(show_playlist {1..7})"
}

preview_playlist() {
	broadcast_id="$1";
	_sql="SELECT s.artist, s.title FROM playlists p  join songs s using (song_id) join broadcasts b using (broadcast_id) join shows sh using (show_id) WHERE b.broadcast_id=$broadcast_id ORDER BY p.start ASC";
	echo "$_sql" | sqlite3 -list db/krcl-playlist-data.sqlite3 | column -s '|' -c 2 -t

}

show_playlist() {
	broadcast_id="$1";
	_sql=$(cat << END_QUERY	
		SELECT 
--			p.start
--			(SELECT b2.start FROM broadcasts b2 WHERE b2.broadcast_id=$broadcast_id),
			strftime('%s', p.start) - (SELECT strftime('%s', b2.start) FROM broadcasts b2 WHERE b2.broadcast_id=$broadcast_id)
		FROM playlists p 
			join songs s using (song_id) 
			join broadcasts b using (broadcast_id) 
			join shows sh using (show_id) 
		WHERE
			p.start < (SELECT p2.start FROM playlists p2 WHERE p2.broadcast_id = ${broadcast_id} ORDER BY p2.start DESC limit 1)
			AND b.broadcast_id < $broadcast_id
--		AND
--			p.end > (SELECT p2.end FROM playlists p2 WHERE p2.broadcast_id = $broadcast_id ORDER BY p2.start DESC limit 1 )
		ORDER BY p.start DESC
		LIMIT 1;

END_QUERY
);

	_offset=$(sqlite3_query "$_sql")
	export _skip=$(( $_offset * 1024 / 8 ));

#--		( SELECT strftime('%s', p2.start) - strftime('%s', broadcast_start) FROM playlists p2 WHERE p2.start < broadcast_start ORDER BY p2.start DESC LIMIT 1) ,
	_sql=$(cat << END_QUERY	
	SELECT 
		artist, 
		title, 
		pos, 
		len,
--		$_skip,
		"${_KRCL_STREAM_CACHEDIR}stream-b" || broadcast_id || "-p" || playlist_id || "-s" || song_id || "-sh" || show_id || ".mp3",
		( (pos * $_KRCL_BITRATE * 1024 / 8) + $_skip) AS range_start,
		( ( (pos+len) * $_KRCL_BITRATE * 1024 / 8) + $_skip) AS range_end,
		audiourl
	FROM (
		SELECT 
			s.artist,
			s.title, 
			strftime('%s', p.start) - strftime('%s', b.start) AS pos,
			strftime('%s', p.end) - strftime('%s', p.start) AS len,
			-- strftime("%Y-%m-%d %H:%M:%S", p.start) AS start,
			-- strftime('%s', b.start) AS broadcast_start,
			b.start - $_skip AS broadcast_start,
			p.playlist_id,
			s.song_id, 
			b.broadcast_id,
			sh.show_id,
			b.audiourl
		FROM playlists p 
			join songs s using (song_id) 
			join broadcasts b using (broadcast_id) 
			join shows sh using (show_id) 
		WHERE
			b.broadcast_id=$broadcast_id
		ORDER BY p.start ASC
	)
END_QUERY
);
	echo -e "\r\nshow_playlist:\r\n$_sql"  >> $_KRCL_LOGFILE;

	export -f do_curl
	export _CURL_PID
	info=$(echo "$_sql" | sqlite3 -list db/krcl-playlist-data.sqlite3 \
	| column -s '|' -c 3 -t \
	| tee -a $_KRCL_LOGFILE \
	| fzf --reverse --disabled \
		--preview-window=top,20%,nofollow,nowrap \
		--header "The header" \
		--bind "alt-up:execute(ncat_vlc volup)" --bind "alt-down:execute(ncat_vlc voldown)" --bind "ctrl-space:execute(ncat_vlc pause)" --bind "alt-left:execute(ncat_vlc 'seek -5')" --bind "alt-right:execute(ncat_vlc 'seek +5')" \
		--bind "esc:abort" \
		--bind "home:abort" \
		--bind "enter:preview:do_curl {}" \
		--bind "double-click:preview:do_curl {}" \
		);
}
do_curl() {
	pkill --full 'curl.*krcl.*mp3$'

	#ncat_vlc "stop" "clear" 
	echo -e "\r\ndo_curl: \$\* $*" >> $_KRCL_LOGFILE;
	trackinfo=$(echo "$*" | sed -r 's/ {2} +/\|/g' | awk -F'|' '{print $1" - " $2 }');
	info=$(echo "$*" | rev | sed 's/  */ /g' | cut -d" " -f1-4 | rev);
	tmux set-option display-time 1500
	tmux display-message "Streaming $trackinfo"
	echo -e "\r\ndo_curl: info: ${info}" >> $_KRCL_LOGFILE;

	_cachefile=$(echo "$info" | cut -d" " -f1);
	_rangefrom=$(echo "$info" | cut -d" " -f2);
	_rangeto=$(echo "$info" | cut -d" " -f3);
	_url=$(echo "$info" | cut -d" " -f4);
	#curl -C 1298432 -v --progress-bar --retry 10 --retry-delay 2 -A chrome \

	#curl_opts="--output $_cachefile -r ${_rangefrom}-${_rangeto} $_url";
	curl_opts="--output - -r ${_rangefrom}-${_rangeto} $_url";
	
	echo "do_curl: curl_opts:$curl_opts"  >> $_KRCL_LOGFILE;

	curl_cmd="curl -v --progress-bar --retry 10 --retry-delay 2 -A chrome $curl_opts"

#	`$curl_cmd 2>> $_KRCL_LOGFILE | pv -p -t -e -b -r --force --size $(( ${_rangeto} - ${_rangefrom} )) 2> "${_KRCL_LOGFILE}.progress" >> $_cachefile &`

	curl -v --progress-bar --retry 10 --retry-delay 2 -A chrome \
		$curl_opts 2>> $_KRCL_LOGFILE \
		| pv -p -t -e -b -r --force --size $(( ${_rangeto} - ${_rangefrom} )) 2> "${_KRCL_LOGFILE}.progress" >> $_cachefile &

#	_CURL_PID=$(pgrep --full "$curl_cmd");

	#echo "_CURL_PID=$_CURL_PID"  >> $_KRCL_LOGFILE;

#	sleep 1s

	while [ ! -s "$_cachefile" ]; do
		sleep 0.25s;
	done

	_min_buffer_filesize=$(( $_KRCL_BUFFER_SECS * $_KRCL_BITRATE * 1024	 / 8 ));
	echo "_min_buffer_filesize $_min_buffer_filesize" >> $_KRCL_LOGFILE

	tmux set-window-option -g window-status-current-format ""
	tmux set-option -g status-justify "centre"
	tmux set-option -g status-left-length 80	
	tmux set-option -g status-right-length 80	
	tmux set-option -g status-right "#(cat ${_KRCL_LOGFILE}.progress | tr '\r' '\n' | tail -n1)"
	tmux set-option -g status-interval 1

	while [ `stat -c "%s" "$_cachefile"` -lt "$_min_buffer_filesize" ]; do
		per=$(echo "`stat -c '%s' $_cachefile` / $_min_buffer_filesize * 100"  | bc -l | xargs printf "%0.0f");
		tmux set-option status-left "Buffering ${per}%"
		sleep 0.25s
	done	


	ncat_vlc "clear" 
	ncat_vlc "loop on" 
	ncat_vlc "add `readlink -e $_cachefile`"
	tmux set-option status-left "$trackinfo    "


	#stdbuf -i0 -o0 tail -f "${_KRCL_LOGFILE}.progress" | tr "\r" "\n" > /dev/stderr &
	#while [ `pgrep -c curl` > 0 ]; do
		#( tail -F "${_KRCL_LOGFILE}.progress" > /dev/stderr ) & 
	#	sleep 0.1
	#done
}

ncat_vlc() {
	#Login
	_cmd="123456\r\n";
	for verb in "$@"; do
		_cmd="${_cmd}${verb}\r\n";
	done
	echo -e "ncat_vlc: ${_cmd}" >> $_KRCL_LOGFILE
	echo -ne "${_cmd}" | ncat -t localhost 23456 2>&1 >> /tmp/krcl_ncat.log
}

sqlite3_query() {
	_sql="$1";
	_res=$(sqlite3 -list db/krcl-playlist-data.sqlite3 "$_sql");
	if [[ $? != 0 ]]; then
		echo "Sqlite3 $_res"
		exit 1;
	fi
	echo "$_res";
}

export -f sqlite3_query
export -f broadcast_list
export -f preview_playlist
export -f show_playlist
export -f do_curl
export -f ncat_vlc

cleanup() {
	rm $_KRCL_LOGFILE
	rm "${_KRCL_LOGFILE}.progress"
	pkill --full "$_cvlc_cmd"

}

trap cleanup EXIT

broadcast_list




#_p=1840;_skip=0; _rate=192;_s=$(($_p + 3000)); curl -A 'Chrome' 
#-r $(( ($_p * $_rate*1024 / 8)+($_skip) ))-$(( ($_s * $_rate * 1024/8) + ($_skip) )) 'https://krcl-media.s3.us-west-000.backblazeb2.com/audio/afternoon-delight/afternoon-delight_2023-02-11_13-00-00.mp3' | cvlc -

