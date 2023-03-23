#!/usr/bin/env perl

# git add, commit and push in one go.
# https://codeberg.org/anhsirk0/gacp

use strict;
use Cwd qw( getcwd abs_path );
use File::Basename qw( fileparse );
use File::Find;
use File::Spec::Functions qw( abs2rel catfile splitpath );
use Getopt::Long;
use List::Util qw( min max );
use Term::ANSIColor;
use warnings;

# for cli args
my @add_files     = ();
my @exclude_files = ();
my $DRY_RUN;
my $HELP;
my $LIST;
my $DONT_PUSH;
my $DONT_IGNORE;
my $RELATIVE_PATHS;

my $TOP_LEVEL;
my $PATH_SEP       = catfile("", "");
my @ADDED          = ();
my @EXCLUDED       = ();
my $COMMIT_MESSAGE = $ENV{GACP_DEFAULT_MESSAGE} || "updated README";
my $MAX_COLS       = 30;


# colors
my %COLOR = (
    "GREEN"    => "bright_green",
    "YELLOW"   => "yellow",
    "GREY"     => "bright_black",
    "MAGENTA"   => "bright_magenta",
    "RED"  => "bright_red",
    "CYAN"      => "bright_cyan",
    "BLUE"     => "bright_blue"
    );

# git status codes
my %STATUS = (
    "STAGED"   => "A",
    "MODIFIED" => "M",
    "DELETED"  => "D",
    "NEW"      => "??"
    );

my @files_inside_new_dirs = ();

sub set_top_level {
    chomp($TOP_LEVEL = `git rev-parse --show-toplevel`);
}

sub inside_a_git_repo {
    return `git rev-parse --is-inside-work-tree 2> /dev/null` eq "true\n"
}

# This is used as a Type
# This returns reference to a HASH
sub to_git_file {
    my ($status, $abs_path, $rel_path) = @_;
    # if paths has space in them
    if ($abs_path =~ m/ /) {
        $abs_path = q/"/ . $abs_path . q/"/;
    }
    if ($rel_path =~ m/ /) {
        $rel_path = q/"/ . $rel_path . q/"/;
    }

    return {
        "status" => $status,
            "abs_path" => $abs_path,
            "rel_path" => $rel_path
    }
}

# convert arguments to empty git_files
# This returns reference to a HASH
sub arg_to_git_file {
    my ($rel_path) = @_;
    $rel_path =~ s/^:$PATH_SEP:/$TOP_LEVEL$PATH_SEP/;
    return to_git_file("", abs_path($rel_path), $rel_path)
}

# Read repo_name.ignore file and return file_paths
sub get_auto_excluded_files {
    my @auto_excluded_files = ();
    my $data_dir = ($^O eq "MSWin32") ? $ENV{APPDATA} :
        catfile($ENV{HOME}, ".config");
    return () unless $data_dir;

    my ($_volume, $_dir, $repo_name) = splitpath($TOP_LEVEL);
    my $ignore_file = catfile($data_dir, "gacp", $repo_name . ".ignore");
    return () unless (-f $ignore_file);

    open(FH, "<", $ignore_file) or die "Unable to open $ignore_file\n";
    while(<FH>) {
        for ($_) {
            s/\#.*//;  # ignore comments
            s/\s+/ /g; # remove extra whitespace
            s/^\s+//;  # strip left whitespace
            s/\s+$//;  # strip right whitespace
            s/\/$//;   # strip trailing slash
        }
        next unless $_;
        push(@auto_excluded_files, $_);
    }
    close(FH);

    return @auto_excluded_files
}

# path relative to toplevel in git style or relative path
sub to_git_path {
    my ($path) = @_;
    my $rel_path = abs2rel($path);
    return $rel_path if $RELATIVE_PATHS;

    my $rel_path_to_top_level = abs2rel($path, $TOP_LEVEL);
    if ($rel_path =~ m/^\.\./) {
        $rel_path = ":$PATH_SEP:" . $rel_path_to_top_level;
    }
    return $rel_path
}

# wanted sub for finding files
sub wanted {
    my $file_name = $File::Find::name;
    return unless (-f);
    push(@files_inside_new_dirs, $file_name);
}

# Parse git_status line by line,
# Returns a list of GitFile
# if any path is a directory, this func will adds all its files recursively
# relative paths are relative to TOP_LEVEL unless `RELATIVE_PATHS`
sub parse_git_status {
    my @git_files = ();
    chomp(my $git_status = `git status --porcelain`);
    return () unless $git_status;

    foreach my $line (split "\n", $git_status) {
        my ($status, $file_path) = $line =~ /^\s*([^\s]*?)\s+(.*)$/;
        $file_path =~ s/"//g;

        my $abs_path = catfile($TOP_LEVEL, $file_path);

        unless (-d $abs_path) {
            push(@git_files,
                 to_git_file($status, $abs_path, to_git_path($abs_path)));
            next;
        }
        # $abs_path is a directory from this point
        @files_inside_new_dirs = ();
        find({ wanted => \&wanted }, $abs_path);
        foreach my $f (@files_inside_new_dirs) {
            push(@git_files, to_git_file($status, $f, to_git_path($f)));
        }
    }
    return @git_files;
}

sub is_git_file_in {
    my ($arr_ref, $git_file) = @_;
    my $git_file_path = $$git_file{abs_path};
    # if files that has spaces in them, remove their quotes
    $git_file_path =~ s/"//g;

    for (@$arr_ref) {
        my $file_path = $$_{abs_path};

        # if files that has spaces in them, remove their quotes
        $file_path =~ s/"//g;
        return 1 if (-f $file_path && $file_path eq $git_file_path);

        # $file_path is a dir
        my $dir = $file_path . $PATH_SEP;
        return 1 if ($git_file_path =~ m/^$dir/)
    }
    return 0
}

# Returns reference to files_to_add and files_to_exclude
sub get_added_excluded_files {
    my @files_to_add = ();
    my @files_to_exclude = ();
    for my $file (@_) {
        my $chars = length($$file{rel_path});
        $MAX_COLS = $chars if $chars > $MAX_COLS;
        if (is_git_file_in(\@EXCLUDED, $file)) {
            push(@files_to_exclude, $file);
            next;
        }
        if (is_git_file_in(\@ADDED, $file) || scalar(@ADDED) == 0) {
            push(@files_to_add, $file);
        }
    }
    return (\@files_to_add, \@files_to_exclude)
}

sub git_add_commit_push {
    my ($added_files) = @_;
    return unless $added_files;

    print "\n";
    my $prev_return = system("git add " . $added_files);
    return unless ($prev_return eq "0");

    $prev_return = system("git commit -m '" . $COMMIT_MESSAGE . "'");
    return unless ($prev_return eq "0" && !$DONT_PUSH);

    system("git push");
}

sub get_heading {
    my ($title, $total) = @_;
    return "$title ($total file" . ($total > 1 && "s") . "):\n";
}

sub print_git_file {
    my ($git_file, $idx, $color) = @_;
    my $label;

    my $status = $$git_file{status};
    my $file = $$git_file{rel_path};

    if ($status eq $STATUS{NEW}) {
        $color ||= $COLOR{CYAN};
        $label = "new";
    } elsif ($status eq $STATUS{MODIFIED}) {
        $color ||= $COLOR{GREEN};
        $label = "modified";
    } elsif ($status eq $STATUS{STAGED}) {
        $color ||= $COLOR{MAGENTA};
        $label = "staged";
    } elsif ($status eq $STATUS{DELETED}) {
        $color ||= $COLOR{RED};
        $label = "deleted";
    } else {
        $color ||= $COLOR{GREY};
        $label = $status;
    }
    my $format = "%6d) %-" . $MAX_COLS . "s %12s\n";
    print colored(sprintf($format, $idx, $file, "($label)"), $color);
}

sub format_option {
    my ($short, $long, $desc, $args, $default) = @_;
    my $GREEN = $COLOR{GREEN};
    my $tabs = "\t" . (length($short . $long . $long x $args) < 11 && "\t");
    my $text = "\t" . colored("-" . $short, $GREEN);
    $text .= ", " . colored("--" . $long . " ", $GREEN);
    $text .= ($args > 0 && colored("<" . uc $long . ">", $GREEN)) . $tabs;
    $text .= $desc . ($default ne 0 && " [default: " . $default . "]");
    return $text . "\n";
}

sub print_help_and_exit {
    # This is a mess
    printf(
        "%s\n\n%s\n\n" .            # About, Usage
        "%s \n%s%s%s%s%s%s%s%s\n" . # Options list
        "%s\n%s %s\n " .            # Args
        "\n%s\n%s\n%s %s\n%s %s\n", # Examples
        colored("gacp", $COLOR{GREEN}) . "\ngit add, commit & push in one go.",
        colored("USAGE:", $COLOR{YELLOW}) . "\n\t" . "gacp [ARGS] [OPTIONS]",
        colored("OPTIONS:", $COLOR{YELLOW}),
        format_option("h", "help", "Print help information", 0, 0),
        format_option("l", "list", "List new/modified/deleted files", 0, 0),
        format_option("d", "dry", "Dry-run (show what will happen)", 0, 0),
        format_option("r", "relative-paths", "Enable Relative paths", 0, 0),
        format_option(
            "ni", "no-ignore",
            "Don't auto exclude files specified in gacp ignore file",
            0, 0
        ),
        format_option("np", "no-push", "No push (Only add and commit)", 0, 0),
        format_option("f", "files", "Files to add (git add)", 1, "-A"),
        format_option("e", "exclude", "Files to exclude (not to add)", 1, 0),
        colored("ARGS:", $COLOR{YELLOW}),
        colored("\t<MESSAGE>", $COLOR{GREEN}),
        "\t\tCommit message [default: \"updated README\"]",
        colored("EXAMPLES:", $COLOR{YELLOW}),
        "\tgacp " . colored("\"First Commit\"", $COLOR{BLUE}),
        "\tgacp " . colored("\"updated README\"", $COLOR{BLUE}),
        "-f " . colored("README.md", "underline"),
        "\tgacp " . colored("\"Pushing all except new-file.pl\"", $COLOR{BLUE}),
        "-e " . colored("new-file.pl", "underline"),
        );
    exit
}

sub parse_args {
    GetOptions (
        "help|h" => \$HELP,
        "list|l" => \$LIST,
        "dry|d" => \$DRY_RUN,
        "relative-paths|r" => \$RELATIVE_PATHS,
        "no-ignore|ni" => \$DONT_IGNORE,
        "no-push|np" => \$DONT_PUSH,
        "files|f=s{1,}" => \@add_files,
        "exclude|e=s{1,}" => \@exclude_files,
        ) or die("Error in command line arguments\n");
    print_help_and_exit() if $HELP;
}

sub main {
    parse_args();
    die(colored("Not in a git repository", $COLOR{RED}) . "\n")
        unless inside_a_git_repo();

    set_top_level();
    $COMMIT_MESSAGE = $ARGV[0] || $COMMIT_MESSAGE;
    unless ($DONT_IGNORE) {
        for (get_auto_excluded_files()) {
            push(@exclude_files, abs2rel($TOP_LEVEL . $PATH_SEP . $_));
        }
    }
    @ADDED = map { arg_to_git_file $_ } @add_files;
    @EXCLUDED = map { arg_to_git_file $_ } @exclude_files;

    my @parsed_git_status = parse_git_status();

    if ($LIST) {
        for my $f (@parsed_git_status) {
            print $$f{rel_path} . "\n";
        }
        exit;
    }

    my ($files_to_add_ref, $files_to_exclude_ref) = get_added_excluded_files(
        @parsed_git_status);
    my $total_added = scalar(@$files_to_add_ref);
    if ($total_added) {
        print colored(get_heading("Added", $total_added), $COLOR{GREY});
        for my $idx (0 .. $total_added - 1) {
            print_git_file($$files_to_add_ref[$idx], $idx + 1);
        }
        print "\n";
    }
    my $total_excluded = scalar(@$files_to_exclude_ref);
    if ($total_excluded) {
        print colored(get_heading("Excluded", $total_excluded), $COLOR{GREY});
        for my $idx (0 .. $total_excluded - 1) {
            print_git_file($$files_to_exclude_ref[$idx], $idx + 1,
                           $COLOR{YELLOW});
        }
        print "\n";
    }

    print colored("Commit message:", $COLOR{GREY}) . "\n";
    print colored(sprintf("%6s%s", "", $COMMIT_MESSAGE), $COLOR{BLUE}) . "\n";

    exit if $DRY_RUN;
    die(colored("\nNo files to add", $COLOR{RED}) . "\n") unless $total_added;

    my $added_files = join(" ", map { $$_{rel_path} } @$files_to_add_ref);
    git_add_commit_push($added_files);
}

main()
