my $verbose=1 if $ENV{VERBOSE};

#--------------------------------------------------------------------------------

sub parsecsv($) {
    my $line = $_[0];
    my @ret;
    while ($line) {
	if (($line =~ s/^'(.*?)'//) || ($line =~ s/^"(.*?)"//)) { # quoted
	    push(@ret,$1);
	    $line =~ s/^\s*,//; # delete comma
	} elsif ($line =~ s/(.*?)(,|$)//) { # not quoted
	    push(@ret,$1);
	} else {
	    last;
	}
    }
    return @ret;
}

#--------------------------------------------------------------------------------
# print shell command(s) and execute using system()
# return value: exit code from command
sub syscmd(@) {
    print STDERR "exec ", join(" ",map { "'$_'" } @_), "\n" if $verbose;
    return system(@_);
}

#--------------------------------------------------------------------------------
# evaluate command and return its output
sub syseval(@) {
    open X, ">&STDOUT";
    my $temp = "syseval";
    open STDOUT, '>', $temp;
    my $rc=syscmd(@_);
    open STDOUT, ">&X";
    close X;
    return pget_del($temp);
}

#--------------------------------------------------------------------------------
# delete persistent value
sub pdel($) {
    unlink($_[0]);
    print STDERR "del $_[0]\n" if $verbose;
}

#--------------------------------------------------------------------------------
# persistent set key:$_[0] to value $_[1]
# return value: status code
sub pset($$) {
    open(my $fh, '>', $_[0]);
    print $fh $_[1];
    print STDERR "set $_[0] = $_[1]\n" if $verbose;
    return close $fh;
}

# like pset, but empty value string means pdel
sub pset_ne($$) {
    if ($_[1] eq "") {
	pdel($_[0]);
    } else {
	pset($_[0],$_[1]);
    }
}

#--------------------------------------------------------------------------------

sub pexists($) {
    return -f $_[0];
}

#--------------------------------------------------------------------------------
# persistent get value for key:$_[0]
sub pget($) {
    local $/ = undef;
    my $ret;
    if (open my $fh, "<", $_[0]) {
	$ret = <$fh>;
    }
    print STDERR "get $_[0] = $ret\n" if $verbose;
    return $ret;
}

# get value and delete persisted value
sub pget_del($) {
    my $ret=pget($_[0]);
    pdel($_[0]);
    return $ret;
}

#--------------------------------------------------------------------------------

sub urlencode {
    my $s = shift;
    $s =~ s/ /+/g;
    $s =~ s/([^:A-Za-z0-9\+-])/sprintf("%%%02X", ord($1))/seg;
    return $s;
}

#--------------------------------------------------------------------------------

sub trimstr($$) {
    my $ret=substr( $_[0], 0, $_[1]-3 );
    return ($ret eq $_[0] ? $ret : "$ret...");
}

#--------------------------------------------------------------------------------

sub keyval($$) {
    my $val;
    if (ref($_[1]) eq 'HASH') {
	use JSON;
	$val=to_json($_[1]);
    } else {
	$val=$_[1];
    }
    return "  $_[0]:'$val'";
}

#--------------------------------------------------------------------------------

sub prerr {
    print STDERR join(" ",@_),"\n";
}

#--------------------------------------------------------------------------------

sub prlog {
    print join(" ",@_),"\n";
}

1;

