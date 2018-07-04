#!/usr/local/bin/perl
use strict;
use warnings;
use JSON qw(to_json decode_json);    
use HTML::Entities;
use File::Basename;
my $thisdir=dirname($0);
require "$thisdir/lib.pl";

# find google take out data under $HOME/Downloads
# extract it into a temporary directory, decompress
# scan for playlists and output them as a json object.

# google takeout format is 1 csv file per track.
# CSV file looks like this:
# Title,Album,Artist,Duration (ms),Rating,Play Count,Removed,Playlist Index
# "Stepping Stone","Rockferry","Duffy","209000","0","3","","8"

# output of this script:
# json object
# {
#   tracks: [
#       { track:""  // primary key
#         , playlist:""
#         , title:""
#         , album:""
#         , artist:""
#         , rating:""
#         , play_count:""
#         , playlist_index:"" }
#      ,{ ... }
#   ]
# }

#--------------------------------------------------------------------------------

my $g_output={};
my $tracks_total=0;
my $tracks_matched=0;
$g_output->{tracks} = [];

#--------------------------------------------------------------------------------

# add track object to output
sub push_track($) {
    my $tracks=$g_output->{tracks};
    push(@$tracks,$_[0]);
}

#--------------------------------------------------------------------------------

# add track object to output
sub print_output() {
    print to_json($g_output, {pretty=>1});
}

#--------------------------------------------------------------------------------

sub import_playlist_dir($$) {
    my $playlist=basename($_[0]);
    my $regx=$_[1];
    my @list;
    print STDERR "    import  name:$playlist  dir:$_[0]\n";
    foreach my $file(glob("\"$_[0]/Tracks/\"*.csv")) {
	my $good=0;
	foreach my $line(split("\n",pget($file))) {
	    if ($line =~ /^Title,Album,Artist.*/) {
		$good=1;
	    } elsif ($good) {
		push(@list,$line);
	    }
	}
    }
    foreach my $line(@list) {
	# Title,Album,Artist,Duration (ms),Rating,Play Count,Removed,Playlist Index
	my @fields=parsecsv($line);
	my $track={};
	# let's go out on a limb and say that a playlist cannot contain
	# more than one track with the same title
	$tracks_total++;
	$track->{playlist}=$playlist;
	$track->{title}=decode_entities($fields[0]);
	$track->{album}=decode_entities($fields[1]);
	$track->{artist}=decode_entities($fields[2]);
	$track->{rating}=decode_entities($fields[4]);
	$track->{play_count}=$fields[5];
	$track->{playlist_index}=$fields[7];
	$track->{track}="$playlist/$track->{title}";
	# track/album cannot be empty
	if ($fields[0] && $fields[1] && ($track->{track} =~ /$regx/)) {
	    $tracks_matched++;
	    push_track($track);
	}
    }
}

#--------------------------------------------------------------------------------

# look for google takeout files under ~/Downloads
# unpack them, and import any Google Play Music playlists into spotify
my $regx = (shift @ARGV) || ".*";
my $file=$ENV{HOME} . "/Downloads/takeout-*.zip";
my @files = glob("$file");
foreach my $file(@files) {
    print STDERR "Process $file\n";
    my $filename=basename($file);
    syscmd("rm -rf temp/playlists
	   mkdir -p temp/playlists
	   cp $file temp/playlists
	   cd temp/playlists && unzip -q $filename 2>/dev/null
	   ");
    foreach my $pldir (glob("\"temp/playlists/Takeout/Google Play Music/Playlists/\"*")) {
	if (-d $pldir) {
	    import_playlist_dir($pldir,$regx);
	}
    }
}
#syscmd("rm -rf temp/playlists");

print_output();
print STDERR "Done. Tracks total:$tracks_total  matched:$tracks_matched\n";
exit 0;
