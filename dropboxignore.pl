#!/usr/bin/perl

use warnings;
use strict;

use constant DEBUG => 1;
use File::Path "make_path";
use Cwd "abs_path";

my $real = abs_path($ARGV[0]);
my $linked = abs_path($ARGV[1]);
my $ignorefile = ".dropboxignore";

my %linked_files;

debug("Real is $real\nLinked is $linked\n");

sub debug {
	my $pretxt;
	if (defined($_[1])) {
		for (0..$_[1]-1) { 
			$pretxt .= "\t";
		}
	}
	$pretxt .= "DEBUG: ";
	print STDERR "$pretxt$_[0]" if DEBUG;
}

sub daemonize {
	my $pid = fork();

	if (!$pid) {
		&{$_[0]};
	} else {
		print "Child is $pid\n";
		exit 0;
	}
}

sub dosymlink {
	my ($sourcedir, $targetdir, $file) = @_;
	debug("Making symlink for $file\n");
	if (-e "$targetdir/$file") {
		debug("Link already exists!\n", 1);
		return;
	}
	if (!-e $targetdir) {  # Create folder if it doesn't exist
		make_path($targetdir);
	}
	debug("Linking $sourcedir/$file to $targetdir/$file");
	symlink("$sourcedir/$file", "$targetdir/$file");
}

sub loadignore {
	my ($base, $subdir) = @_;
	my $fulldir = "$base/$subdir";
	my ($dh, $IGN_FILE);
	if (!opendir($dh, "$fulldir") ||
		!open($IGN_FILE, "<$fulldir/$ignorefile")) {
		die if DEBUG;
		return -1;
	}
	my @files = readdir($dh);
	my %to_link = map { $_ => 1 } @files;

	my @no_link;

	while(my $line = readline($IGN_FILE)) {
		chomp $line;
		foreach my $file (@files) {
			# We don't want to link to "." or ".."
			if ($file =~ m/^(\.){1,2}$/ || -d "$fulldir/$file") {
				next;
			}
			elsif ($file !~ m/$line/) {
				debug("$file doesn't match \"$line\"\n");
			} else {
				debug("$file matches \"$line\"\n");
				push(@no_link, $file);
			}
		}
	}
	debug("\@no_link = @no_link\n");
	delete @to_link{@no_link};

	foreach my $file (keys %to_link) {
		if (!-e "$linked/$subdir/$file") {
			if ($linked_files{"$fulldir/$file"}) {
				debug("Original $file has been deleted\n");
				unlink "$fulldir/$file";
				delete $linked_files{"$fulldir/$file"};
			} elsif (!-d "$fulldir/$file") {
				dosymlink($fulldir, "$linked/$subdir", $file);
				debug("Linked $fulldir/$file\n");
				$linked_files{"$fulldir/$file"} = 1;
			}
		}
	}

	# Search in linked folder for extra links
	opendir($dh, "$linked/$subdir");
	foreach my $file (readdir $dh) {
		if (!defined($to_link{$file})) {
			unlink "$linked/$subdir/$file";
		}
	}
}

sub iterate {
	# Remains constant
	my ($prefix, $dir) = @_;
	if (!$dir) {
		$dir = ".";
	}

	#print "Checking $prefix/$dir/$ignorefile\t| ";
	my $loadall;

	if (-e "$prefix/$dir/$ignorefile") {
		#	print "Yes\n";
		loadignore($prefix, $dir);
	} else {
		#print "No\n";
		$loadall = 1;
	}

	my $dh;
	if (!opendir($dh, "$prefix/$dir")) {return -1;}
	foreach my $item (readdir($dh)) {
		my $special = $item =~ m/^(\.){1,2}$/;
		debug("$item\n", 1);
		if (-d "$prefix/$dir/$item" && !$special) {
			debug("Going to $dir/$item\n\n");
			iterate($prefix, "$dir/$item");
			debug("Back in $prefix/$dir:\n");
		} elsif (defined($loadall) && -f "$prefix/$dir/$item") {
			dosymlink("$prefix/$dir", "$linked/$dir", $item);
		}
	}
	debug("Backing out...\n\n");
}

sub main {
	while (!(-e "/var/lock/stopdropboxignore")) {
		iterate($real);
	}
}

if (-d $real) {
	print "Directory already exists, are you sure you want to continue?[y/n] ";
	exit 0 if !(<STDIN> =~ /^y$/);
}

daemonize(\&main);
