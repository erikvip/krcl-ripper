 #!/usr/bin/php7.3

<?php
# @ TODO
# The timezones are screwed up...the broadcast data reports it's in UTC timezone and it is
# But the Playlist data reports UTC but *IT'S NOT UTC*. It's America/Denver, but claims Greenwich...
# This screws w/ all the date handling code...
# Need to normalize / fix the timezone data...

$db = new SQLite3('db/krcl-playlist-data.sqlite3');
$db->enableExceptions(true);

$broadcast_file=$_SERVER['argv'][1];
if (is_numeric($broadcast_file)) {
	$bid = $broadcast_file;
	$where="broadcast_id=" . $bid;
} else {
	$where="audiourl LIKE '%".$db->escapeString(basename($broadcast_file)) . "'";
}

$fileprefix="mp3/";
if ( isset($_SERVER['argv'][2]) ) {
	$fileprefix=$_SERVER['argv'][2];
}
if ( substr($fileprefix, strlen($fileprefix)-1, 1)  != "/" ) {
	$fileprefix.="/";
}


$outputpath="";
if ( isset($_SERVER['argv'][3]) ) {
	$outputpath=$_SERVER['argv'][3];
}


function query($query) {
	global $db;
	$result = $db->query($query); 
	$output=[];
	while ($r = $result->fetchArray(SQLITE3_ASSOC)) {
		$output[]=$r;
	}
	return $output;
}

$sql="SELECT 
	b.broadcast_id,
	s.show_id, 
	s.name, 
	s.title as show_title,
	b.start, 
	b.end, 
	b.audiourl, 
	b.title
	FROM broadcasts b 
		JOIN shows s USING (show_id) 
	WHERE $where";

$broadcast=query($sql);

$bid=$broadcast[0]['broadcast_id'];
#$q = "select (select strftime('%s', start) - strftime('%s',datetime(b.start,'-7 hour')) from playlists where broadcast_id=94191 order by start limit 1) as duration,datetime(start, '-7 hour') AS start,datetime(b.end, '-7 hour') as end,'Intro' as title,'NA' as artist, 'NA' as album from broadcasts b where broadcast_id=94191 UNION select strftime('%s', end) - strftime('%s', start) AS duration, start, end, title, artist, album from playlists p join songs using (song_id) where broadcast_id=94191 order by start ;";
$q="
	SELECT 
		p.*, 
		s.*, 
		b.start AS show_start, 
		b.end AS show_end, 
		STRFTIME('%s', b.start) AS unix_show_start, 
		STRFTIME('%s', b.end) AS unix_show_end,
		STRFTIME('%s', p.start) AS unix_song_start, 
		STRFTIME('%s', p.end) AS unix_song_end 
	FROM playlists p 
		JOIN songs s USING (song_id) 
		JOIN broadcasts b USING (broadcast_id)
	WHERE p.broadcast_id=$bid 
	ORDER BY p.start 
";
#echo $q;exit;
$playlist=query($q);

if ( count($playlist) < 2 ) {
	echo "ERROR: Playlist appears invalid:\n";
	print_r($playlist);
	echo $q;
	exit(1);
}


$bdate = new DateTime($broadcast[0]['start'], new DateTimeZone('UTC'));
$bdate->setTimeZone(new DateTimeZone('America/Denver'));

$b = explode("/", $broadcast[0]['audiourl']);

ob_start();
echo "PERFORMER \"KRCL\"\n";
echo "TITLE \"{$broadcast[0]['title']}\"\n";
echo "FILE \"{$fileprefix}$b[5]\" MP3\n";
echo "TRACK 01 AUDIO\n";
echo "\tPERFORMER \"KRCL\"\n";
echo "\tTITLE \"Intro\"\n";

# Some players don't show the first 'Intro' track if it sarts at 0::00 (AIMP on Android)
# Maybe due to "Hidden Track One Audio" on some old CDs...
# So set Track 1 PREGAP to 0:0:00 and then start track at the first frame
echo "\tINDEX 00 0:0:00\n";
echo "\tINDEX 01 0:0:01\n";

$offset=0;
$index=1;
$secs = $bdate->format("U");

foreach($playlist as $i=>$t) {

	# Well thy fixed the mis reporting UTC time zone thing...
	# So if the song start/end is between the broadcsat start end, they're both in UTC
	# But if the song start/end time is outside of the show start /end...then song is in America/Denver
	if ( $t['unix_song_start'] >= $t['unix_show_start'] && $t['unix_song_start'] <= $t['unix_show_end'] )  {
		# show is in UTC (fixed). This happened around 2022-02-14
		$d = new DateTime( substr($t['start'],0,19), new DateTimeZone('UTC'));
		$d->setTimeZone(new DateTimeZone('America/Denver'));
	} else {
		$d = new DateTime( substr($t['start'],0,19), new DateTimeZone('America/Denver'));
	}

	$duration = $d->format("U") - $secs;
	$offset += $duration;
	$index++;

	if (!isset($playlist[($i+1)]))
		break;

	$offset=$duration;

	$ms=0;
	$s=$offset%60;
	$m=floor($offset/60);
	

	$tr = sprintf("%02d", $index);
	echo "TRACK $tr AUDIO\n";
	echo "\tPERFORMER \"{$t['artist']}\"\n";
	echo "\tTITLE \"{$t['title']}\"\n";
	echo "\tINDEX 01 {$m}:{$s}:{$ms}\n";
	echo "\tREM offset: $offset\n";
}


$data=ob_get_contents();

ob_end_clean();

if ($outputpath != "-") {
	if ( $outputpath == "" ) {
		$outputpath = "music/{$broadcast[0]['name']}/";
	}
	if ( strrpos($outputpath, ".cue") !== FALSE ) {
		if ( !file_exists(dirname($outputpath)) ) {		
			mkdir(dirname($outputpath), 0777, true);
		}
		$outfile=$outputpath;
	} else {
		if ( !file_exists($outputpath) ) {		
			mkdir($outputpath, 0777, true);
		}

		if ( substr($outputpath, strlen($outputpath)-1, 1)  != "/" ) {
			$outputpath .= "/";
		}
		$filename=str_replace(".mp3",".cue", basename($broadcast[0]['audiourl']) );
		$outfile=$outputpath . "{$filename}";
	}
	file_put_contents("$outfile", $data);
	fwrite(STDERR, "File saved to {$outfile}" . PHP_EOL);

} else {
	echo $data;
	fwrite(STDERR, "File saved to STDOUT" . PHP_EOL);
}

exit(0);