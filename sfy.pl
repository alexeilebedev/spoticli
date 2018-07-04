# spotify api perl bindings

use warnings;
use strict;

use JSON qw(decode_json to_json);
use MIME::Base64;

# persistent variables used by this module
my $sfy_req_error;
my $sfy_n_searches=0;
my $kclient_id = "sfydata/client_id";
my $kuser_id = "sfydata/user_id";
my $kclient_secret = "sfydata/client_secret";
my $kresponse = "sfydata/response";
my $kaccess_token = "sfydata/client_token";
my $kclient_auth_code = "sfydata/client_auth_code";
my $REDIRECT="http://localhost:12345";
my $verbose=1 if $ENV{VERBOSE};
my $STATE="";

#--------------------------------------------------------------------------------

# initialize client id/secret
sub sfy_init($$) {
    pset($kclient_id,$_[0]);
    pset($kclient_secret,$_[1]);
}

#--------------------------------------------------------------------------------

# request url $_[0] from spotify, using browser request
# return the entire response, as provided to the redirect
# user is given message $_[1] upon success.
# this function is used when we can't use curl -- spotify presents a cloudfront
# bot protector page to some requests -- and these can only be handled in the browser.
# we set up a little server using nc to capture the response
sub sfy_browser_request($$) {
    my $url=$_[0];
    my $msg=$_[1];
    system(q%
echo "HTTP/1.1 200 OK\n\n % . $msg . q%.\n" | nc -l 12345 > % . $kresponse .q% &
pid=$!
# -g=don't bring to foreground; -j=hidden
open -g -j '% . $url . q%'  ## using curl during login presents cloudfront protections
sleep 1
kill $(jobs -p) 2>/dev/null ## kill all remaining jobs -- ignore errors
%);
    return pget_del($kresponse);
}

#--------------------------------------------------------------------------------

# exchange our authorization code for an access token.
# called automatically after login
sub _gettoken() {
    if (!pexists($kaccess_token)) {
	my $client_secret=pget($kclient_secret);
	my $client_id=pget($kclient_id);
	my $client_auth_code=pget($kclient_auth_code);
	my @cmd=("curl"
		 , "-s"
		 , "-d", "client_id=$client_id"
		 , "-d", "client_secret=$client_secret"
		 , "-d", "grant_type=authorization_code"
		 , "-d", "code=$client_auth_code"
		 , "-d", "redirect_uri=$REDIRECT"
		 , "https://accounts.spotify.com/api/token");
	my $resp=sfy_decode_json(syseval(@cmd));
	pset_ne($kaccess_token, $resp->{access_token});
    }
    if (pexists($kaccess_token)) {
	print "Obtained spotify access token. Ready to go!\n";
    }	
}

#--------------------------------------------------------------------------------

# perform spotify login.
# return code is true if operation succeeded.
sub sfy_login() {
    my $client_id = pget($kclient_id);
    my $SCOPE="user-read-private"
	." streaming"
	." app-remote-control" # seek, next, prev
	." user-read-currently-playing"
	." user-modify-playback-state"
	." user-read-playback-state"
	." user-library-read"
	." user-library-modify"
	." user-top-read"
	." playlist-modify-private" # create playlist
	." playlist-read-private" # get list of playlists
	." user-read-recently-played"
	;
    my $url="https://accounts.spotify.com/authorize/"
	."?client_id=$client_id"
	."&response_type=code"
	."&redirect_uri=$REDIRECT"
	."&scope=$SCOPE"
	."&state=$STATE";
    my $resp = sfy_browser_request($url, "spoticli app logged in to Spotify. You can close this tab");
    pdel($kclient_auth_code);
    foreach my $line (split(/\n/,$resp)) {
	# match GET /?code=AQD...BumA&state= HTTP/1.1
	if ($line =~ /^GET .*\?code=(.*?)&.*HTTP/) {
	    pset_ne($kclient_auth_code,$1);
	}
    }
    pdel($kaccess_token);
    if (!pexists($kclient_auth_code)) {
	print STDERR "unable to obtain auth code. not sure what went wrong.\n";
	print STDERR "response was: $resp\n";
    } else {
	_gettoken();
    }
    return pexists($kaccess_token);
}

#--------------------------------------------------------------------------------

# execute regular spotify request, return parsed json
# $_[0]   -- command
# $_[1]   -- GET, PUT, or POST
# $_[2]   -- optional ref to array of request body data keyvals (passed via curl --data)
# $_[3]   -- optional request body
sub sfy_api_req {
    my $url = "https://api.spotify.com/$_[0]";
    my @cmd = ("curl", "-s");
    undef $sfy_req_error;
    push @cmd, ("-H", "Authorization: Bearer ".pget($kaccess_token));
    push @cmd, ("--request", $_[1]);
    # POST fields
    if ($_[2]) {
	my $kvs=$_[2];
	foreach my $kv (@$kvs) {
	    push(@cmd, "-d", $kv);
	}
    }
    # request body
    if ($_[3]) {
	push @cmd, ("--data", $_[3]);
    }
    push @cmd, $url;
    my $resp = sfy_decode_json(syseval(@cmd));
    if ($resp->{error}) {
	$sfy_req_error = "sfy.request_error"
	    .keyval("request",$_[0])
	    .keyval("data",$_[3])
	    .keyval("error", $resp->{error})
	    .keyval("status",$resp->{status});
    }
    return $resp;
}

#--------------------------------------------------------------------------------

# same as above, but attempt re-login if token expired
sub sfy_api_req_retry {
    my $resp=sfy_api_req(@_);
    if ($resp->{error} && $resp->{error}->{status} eq "401") {
	cmd_login();
	$resp=sfy_api_req(@_);
    }
    return $resp;
}

#--------------------------------------------------------------------------------

# retrieve spotify user id
sub sfy_user_id() {
    if (!pexists($kuser_id)) {
	my $resp=sfy_api_req_retry("v1/me","GET");
	pset_ne($kuser_id,$resp->{id});
    }
    return pget($kuser_id);
}

#--------------------------------------------------------------------------------

# clean temporary persistent vars
sub sfy_clean() {
    pdel($kaccess_token);
    pdel($kresponse);
    pdel($kclient_auth_code);
    pdel($kuser_id);
}
    
#--------------------------------------------------------------------------------

# like decode_json but no croak
sub sfy_decode_json($) {
    my $ret={};
    eval {
	$ret=decode_json($_[0]);
	1;
    } or do {
	print STDERR "json_decode_error  $_[0]\n";
    };
    return $ret;
}

#--------------------------------------------------------------------------------

# add track $_[0] to playlist $_[1] at position $_[2]
# return spotify response object
sub sfy_add_track($$$) {
    my ($trackid,$playlistid)=@_;
    my $resp;
    if ($playlistid && $trackid) {
	my $userid=sfy_user_id();
	my $req = {
	    "uris" => ["spotify:track:$trackid"]
	};
	if (defined($_[2])) {
	    $req->{position} = $_[2];
	}
 	$resp=sfy_api_req_retry("v1/users/$userid/playlists/$playlistid/tracks"
				,"POST"
				,undef
				,to_json($req));
    }
    return $resp;
}

#--------------------------------------------------------------------------------
 
sub sfy_resp_okq($) {
     return $_[0] && !$_[0]->{error};
}

#--------------------------------------------------------------------------------

# print last request error to STDERR, if necessary
sub sfy_show_error() {
    if ($sfy_req_error) {
	print STDERR $sfy_req_error . "\n";
    }
    undef $sfy_req_error;
}

#--------------------------------------------------------------------------------

# clear last request error
sub sfy_clear_error() {
    undef $sfy_req_error;
}

#--------------------------------------------------------------------------------

# retrieve spotify request error
sub sfy_req_error() {
    return $sfy_req_error;
}
    
#--------------------------------------------------------------------------------

# find Spotify track by TRACK, ALBUM, ARTIST ($_[0], $_[1], $_[2])
# return track object
sub sfy_find_taa($$$) {
    my ($title,$album,$artist)=@_;
    $sfy_n_searches++;
    my $query="";
    $query .= " track:$title" if $title;
    $query .= " album:$album" if $album;
    $query .= " artist:$artist" if $artist;
    # search for this item
    my $qresp=sfy_api_req_retry("v1/search?q=".urlencode($query)."\&type=track","GET");
    my $items;
    # fetch tracks from response
    if ($qresp) {
	my $tracks=$qresp->{tracks};
	if ($tracks) {
	    $items=$tracks->{items};
	}
    }
    # pick first matching track
    my $ret;
    if ($items) {
	foreach my $item (@$items) {
	    if ($item->{type} eq "track") {
		$ret=$item;
	    }
	}
    }
    # save winning query
    if ($ret) {
	$ret->{query}=$query;
    }
    return $ret;
}

#--------------------------------------------------------------------------------

sub append_message($$) {
    my $item=$_[0];
    if ($item && ($item->{message})) {
	$item->{message} .= "; ";
    }
    $item->{message} .= $_[1];
}

#--------------------------------------------------------------------------------

sub sfy_find_taa_quote($$$) {
    my ($title,$album,$artist)=@_;
    my $item=sfy_find_taa($title,$album,$artist);
    # can this be optimnized?
    if (!$item) {
	$item=sfy_find_taa("'$title'","'$album'","'$artist'");
	append_message($item, "with single quotes");
    }
    if (!$item) {
	$item=sfy_find_taa("\"$title\"","\"$album\"","\"$artist\"");
	append_message($item, "with double quotes");
    }
    return $item;
}

#--------------------------------------------------------------------------------

sub sfy_find_taa_omit($$$) {
    my ($title,$album,$artist)=@_;
    my $item=sfy_find_taa_quote($title,$album,$artist);
    if (!$item) {
	$item=sfy_find_taa_quote($title,$album,"");
	append_message($item, "omitting artist name");
    }
    if (!$item) {
	$item=sfy_find_taa_quote($title,"",$artist);
	append_message($item, "omitting artist name");
    }
    if (!$item) {
	$item=sfy_find_taa_quote(lc($title),lc($album),lc($artist));
	append_message($item, "lowercasing everything");
    }
    return $item;
}

#--------------------------------------------------------------------------------

# same as above, but attempt a few strategies if search doesn't succeed
sub sfy_find_taa_clever($$$) {
    my ($title,$album,$artist)=@_;
    my $nsearches=$sfy_n_searches;
    my $item=sfy_find_taa_omit($title,$album,$artist);
    # try removing ' EP'
    if (!$item && ($album =~ s/ EP$//)) {
	$item=sfy_find_taa_omit($title,$album,$artist);
	append_message($item, "strip 'EP' from album");
    }
    # try removing :'s
    if (!$item && ("$title$album$artist" =~ /:/)) {
	$title =~ s/.*://;
	$album =~ s/.*://;
	$artist =~ s/.*://;
	$item=sfy_find_taa_omit($title,$album,$artist);
	append_message($item, "removing everything to the left of first colon");
    }
    # try removing parentheses
    if (!$item && ($title =~ m/\(/)) {
	$title =~ s/\([^\(]+$//;
	$item=sfy_find_taa_omit($title,$album,$artist);
	append_message($item, "remove last parenthesis from title");
    }
    # try known typos
    # Spotify: SETI Pharos: beacon02..beacon14 is misspelled as beatcon. It's beacon dammit! There are no beats...
    # Spotify: Shpongle's "Walking backwards through the cosmic mirror" is misspelled as "...backwards thought...". Truly.
    # Spotify: Morcheeba's Post Humous is misspelled as "Post Houmous" (Why not post-hummus???)
    if (!$item && ($title =~ /(through|beacon|humous)/i)) {
	$title =~ s/through/thought/i;
	$title =~ s/beacon/beatcon/i;
	$title =~ s/humous/houmous/i;
	$item=sfy_find_taa_omit($title,$album,$artist);
	append_message($item, "with typo replacement");
    }	
    # ? may correspond to a mangled spanish character
    # as in the track Mis dos peque?as, where ? stands for soft n
    if (!$item && ($title =~ m/^(.*)\s+[^\s]+\?.*/)) {
	$title = $1;
	$item=sfy_find_taa_omit($title,$album,$artist);
	append_message($item, "remove word containing ? character");
    }
    # brag about our success
    $nsearches = $sfy_n_searches - $nsearches;
    if ($item->{message}) {
	prerr("Found Track After $nsearches Attempts
ORIGINAL QUERY             track:$_[0] album:$_[1] artist:$_[2]
SUCCESSFUL QUERY          $item->{query}
STRATEGY                  $item->{message}
	      ");
    }
    return $item;
}

1;
