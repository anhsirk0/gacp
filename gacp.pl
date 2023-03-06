#!/usr/bin/env perl

# git add, commit and push in one go.
# https://codeberg.org/anhsirk0/gacp

use strict;
use Cwd qw( getcwd );
use File::Basename qw( fileparse );
use File::Find;
use File::Spec::Functions qw( abs2rel );
use Getopt::Long;
use List::Util qw( max );
use Term::ANSIColor;
use warnings;

# for cli args
my @files_to_add     = ();
my @files_to_exclude = ();
my $dry_run;
my $help;
my $list;
my $dont_push;
my $dont_ignore;
my $relative_paths;

# This tool relies on `git status --porcelain`
# For convenience, `git status --porcelain` is referred as git_status
my @git_status;
my @parsed_git_status;
my @files_inside_new_dirs = ();
my @dirs_to_add           = ();
my @dirs_to_exclude       = ();
my $top_level;

my $COLS       = 72;
my $CONFIG_DIR = $ENV{HOME} . "/.config/gacp";
my $MAX_TOTAL  = 1;

# color constants
my $GREEN     = "bright_green";
my $YELLOW    = "yellow";
my $MOD_COLOR = $GREEN;           # for modified files
my $DEL_COLOR = "bright_red";     # for deleted files
my $NEW_COLOR = "bright_cyan";           # for newly created files
my $EXC_COLOR = $YELLOW;          # for excluded files
my $STG_COLOR = "bright_magenta"; # for staged files
my $STR_COLOR = "bright_blue";    # for string args
my $DOC_COLOR = "bright_white";

# git status codes
my $ADDED_STATUS    = "A";
my $MODIFIED_STATUS = "M";
my $DELETED_STATUS  = "D";
my $NEW_STATUS      = "??";

# pretty formatted and colored options for help message
# params:
#   short    (short name for option : String)
#   long     (long name for option : String)
#   desc     (description for option : String)
#   args     (option accepts args or not : 0|1)
#   default  (default arg for otion : String|0)
# Example return:
#      short, --long <LONG>     Description [default: Default_arg]\n
sub format_option {
    my ($short, $long, $desc, $args, $default) = @_;
    my $tabs = "\t" . (length($short . $long . $long x $args) < 11 && "\t");
    my $text = "\t" . colored($short, $GREEN);
    $text .= ", " . colored("--" . $long . " ", $GREEN);
    $text .= ($args > 0 && colored("<" . uc $long . ">", $GREEN)) . $tabs;
    $text .= $desc . ($default ne 0 && " [default: " . $default . "]");
    return $text . "\n";
}


sub print_help {
    # This is a mess
    printf(
        "%s\n\n%s\n\n%s \n%s%s%s%s%s%s%s%s \n%s\n%s %s\n%s\n%s\n%s %s\n%s %s\n",
        colored("gacp", $GREEN) . "\n" . "git add, commit & push in one go.",
        colored("USAGE:", $YELLOW) . "\n\t" . "gacp [ARGS] [OPTIONS]",
        colored("OPTIONS:", $YELLOW),
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
        colored("ARGS:", $YELLOW),
        colored("\t<MESSAGE>", $GREEN),
        "\t\tCommit message [default: \"updated README\"]",
        colored("EXAMPLE:", $YELLOW),
        "\tgacp " . colored("\"First Commit\"", $STR_COLOR),
        "\tgacp " . colored("\"updated README\"", $STR_COLOR),
        "-f " . colored("README.md", "underline"),
        "\tgacp " . colored("\"Pushing all except new-file.pl\"", $STR_COLOR),
        "-e " . colored("new-file.pl", "underline"),
        );
}


# Pretty print file_name based on their status
# Params:
#     idx        (Index of the file : Int)
#     status     (Status of the file : "??" | "M" | "D")
#     file_name  (Name of the file : String)
#     color      (Color to use for the file : String)
# Example print:
#     modified_file.pl     (modified)
#     newly_created.pl     (new)
#     deleted_file.pl      (deleted)
sub print_file {
    my ($idx, $status, $file_name, $color) = @_;
    my $available_cols = `tput cols`;
    # if `tput cols` return non-zero exit status code
    if ($?) { $available_cols = 88; }
    $available_cols = int($available_cols);

    if ($COLS + 8 > $available_cols) { $COLS = $available_cols; }

    my $label;
    if ($status eq $NEW_STATUS) {
        $color = $color || $NEW_COLOR;
        $label = "new";
    } elsif ($status eq $DELETED_STATUS) {
        $color = $color || $DEL_COLOR;
        $label = "delete";
    } elsif ($status eq $MODIFIED_STATUS) {
        $color = $color || $MOD_COLOR;
        $label = "modified";
    } elsif ($status eq $ADDED_STATUS) {
        $color = $color || $STG_COLOR;
        $label = "staged";
    } else {
        $color = $DOC_COLOR;
        $label = $status;
    }
    printf(
        "    %s %-" . $COLS . "s %s\n",
        colored(" " x (length($MAX_TOTAL) - length($idx)) . "${idx}) ", $color),
        colored("$file_name", $color),
        colored("($label)", $color)
        );
}


sub get_heading {
    my ($name, $total) = @_;
    return "$name ($total file" . ($total > 1 && "s") . "):";
}


# return status and file_path after spliting the $line
# Example:
# $line = " ?? new/file.pl"
# -> $status = "??", $file_path = "new/file.pl"
sub get_status_and_path {
    my ($line) = @_;
    $line =~ s/\/$//; # remove trailing slash
    my ($status, $file_path) = $line =~ /([^\s]*?)\s+([^\s]*)$/;
    return ($status, $file_path)
}


# Populate @dirs_to_add by choosing dir from @files_to_add
# Populate @dirs_to_exclude by choosing dir from @files_to_exclude
# Example:
#    @files_to_add = ["file1.pl", "dir1"]
#  then:
#    @dirs_to_add = ["dir1"]
sub get_dirs_from_files_arr {
    my (@files_arr) = @_;
    my @dirs = ();
    foreach my $f (@files_arr) {
        unless (-d $f) { next }
        $f =~ s/\/$//; # remove trailing slash
        push(@dirs, $f)
    }
    return @dirs;
}

sub update_dirs_to_add {
    @dirs_to_add = get_dirs_from_files_arr(@files_to_add)
}

sub update_dirs_to_exclude {
    @dirs_to_exclude = get_dirs_from_files_arr(@files_to_exclude);
}


# Read $CONFIG_DIR/repo.ignore and return ignored files
sub get_ignored_files {
    my @ignored_files = ();
    my ($repo) = fileparse($top_level);
    my $ignore_file = $CONFIG_DIR . "/" . $repo . ".ignore";
    unless (-f $ignore_file) { return () }

    open(FH, "<" . $ignore_file) or die "Unable to open $ignore_file";
    while(<FH>) {
        for ($_) {
            s/\#.*//;  # ignore comments
            s/\s+/ /g; # remove extra whitespace
            s/^\s+//; # strip left whitespace
            s/\s+$//; # strip right whitespace
            s/\/$//;   # strip trailing slash
        }
        unless ($_) { next }
        push(@ignored_files, $_);
    }
    close(FH);
    return @ignored_files;
}


# wanted sub for finding files
sub wanted {
    my $file_name = $File::Find::name;
    # my $file = (split "/", $file_name)[-1];
    unless (-f) { return }
    push(@files_inside_new_dirs, $file_name);
}


# Check for auto excluding an file
# return 1 if $file is in @ignored_files
sub is_file_auto_ignored {
    my ($file_path, $rel_path, @ignored_files) = @_;
    unless (@ignored_files) { return 0 }

    $rel_path =~ s/:\/://;
    $file_path =~ s/:\/://;

    my $rel_top_path = abs2rel(getcwd(), $top_level);
    if ($rel_path eq ".") { $file_path = $rel_top_path . "/" . $file_path }

    foreach my $i (@ignored_files) {
        my $rgx = qr/^$i$/;
        if (-d $top_level . "/" . $i) { $rgx = qr/^$i/ }
        if ($file_path =~ /$rgx/) { return 1 }
    }

    return 0
}

# handle newly created dirs
# recursively find files inside provide dir (newly created)
# And return array of git_status type lines
# Example:
# ["?? new_dir/sub_dir/file.pl" ...]
sub get_new_dir_git_status {
    my ($file_path, $rel_path, @ignored_files) = @_;
    my @new_dir_statuses = ();
    @files_inside_new_dirs = ();

    # unless (-d $rel_path) { return () } # if not a dir
    find({ wanted => \&wanted }, $rel_path);
    unless (@files_inside_new_dirs) { return () }

    foreach my $f (@files_inside_new_dirs) {
        my ($file_basename, $parent) = fileparse($f);
        my ($cwd_basename) = fileparse(getcwd());
        my ($top_level_basename) = fileparse($top_level);
        if (
            $parent =~ m/($cwd_basename|$top_level_basename)\/$/ ||
            $parent =~ m/^\.\// ||
            $cwd_basename eq $top_level_basename
            ) {
            $f =~ s/^\.\///;
        }
        if ($rel_path =~ m/^\.\.\// && !$relative_paths) {
            $f =~ s/$rel_path\//:\/:$file_path\//;
        }

        if (is_file_auto_ignored($f, $rel_path, @ignored_files)) {
            push(@files_to_exclude, $f);
        }
        push(@new_dir_statuses, $NEW_STATUS . " " . $f);
    }
    return @new_dir_statuses;
}

# This is the core of the whole script
# Updates @parsed_git_status
# $git_status but relative path to current dir
sub parse_git_status {
    # Read ignore file
    my @ignored_files = ();
    unless ($dont_ignore) {
        @ignored_files = get_ignored_files();
    }

    foreach my $line (@git_status) {
        my ($status, $file_path) = get_status_and_path($line);
        my $rel_path = abs2rel($top_level . "/" . $file_path);

        # if a directory is newly created
        # git_status only lists the directory and not the files inside
        if (-d $rel_path) {
            my @new_dir_status = get_new_dir_git_status(
                $file_path,
                $rel_path,
                @ignored_files
                );
            if (@new_dir_status) { push(@parsed_git_status, @new_dir_status) }
            next;
        }

        if ($rel_path =~ m/^\.\.\// && !$relative_paths) {
            $rel_path = ":/:" . $file_path;
        }

        if (is_file_auto_ignored($file_path, $rel_path, @ignored_files)) {
            push(@files_to_exclude, $rel_path);
        }
        push(@parsed_git_status, $status . " " . $rel_path);
    }
}


# Return reference to 2 arrays containing info about added & excluded files
# after parsing `git status --porcelain`
# This function also updates $COLS
# Params:
#    ref_files_to_add      (reference to files_to_add array)
#    ref_files_to_exclude
# Example:
#    `git status --porcelain` = ?? new-file.pl, M mod-file.pl, D del-file.pl
#    @files_to_add = ["mod-file.pl", "del-file.pl"]
#    @files_to_exclude = ["new-file.pl"]
#    will return references to these 2 arrays =>
#    @files_to_add = [["M", "mod-file.pl"], ["D", "del-file.pl"]]
#    @files_to_exclude = [["??", "new-file.pl"]]
sub get_info () {
    # these files will be git added # (@files_to_add - @files_to_exclude)
    my @added_files_info = ();
    my @excluded_files_info = ();

    my $max_width = 1;

    foreach my $line (@parsed_git_status) {
        my ($status, $file_path) = get_status_and_path($line);

        # if file_path has space in them
        if ($file_path =~ m/ / && ! $file_path =~ m/^"/) {
            $file_path = "'" . $file_path . "'";
        }

        if (length($file_path) + 14 > $max_width) {
            $max_width = length($file_path) + 14;
        }

        if (grep /^$file_path$/, @files_to_exclude) {
            push(@excluded_files_info, [$status, $file_path]);
            next;
        }

        my $dir = (split("/", $file_path))[0];
        if (grep /^$dir$/, @dirs_to_exclude) {
            push(@excluded_files_info, [$status, $file_path]);
            next;
        }

        if (grep /^$dir$/, @dirs_to_add) {
            push(@added_files_info, [$status, $file_path]);
            next;
        }

        if (
            $files_to_add[0] ne "-A" &&
            !(grep /^(\.\/)?$file_path$/, @files_to_add)
            ) {
            next
        }

        push(@added_files_info, [$status, $file_path]);
    }

    $COLS = $max_width;
    return (\@added_files_info, \@excluded_files_info);
}


sub main {
    GetOptions (
        "help|h" => \$help,
        "list|l" => \$list,
        "dry|d" => \$dry_run,
        "relative-paths|r" => \$relative_paths,
        "no-ignore|ni" => \$dont_ignore,
        "no-push|np" => \$dont_push,
        "files|f=s{1,}" => \@files_to_add,
        "exclude|e=s{1,}" => \@files_to_exclude,
        ) or die("Error in command line arguments\n");

    if ($help) {
        print_help();
        exit;
    }

    unless (`git rev-parse --is-inside-work-tree 2> /dev/null` eq "true\n") {
        print "Not in a git repository\n";
        exit;
    }

    # set $top_level, $git_status
    chomp($top_level = `git rev-parse --show-toplevel`);
    chomp(my $git_status_porcelain = `git status --porcelain`);
    @git_status = split("\n", $git_status_porcelain);

    # If nothing to commit
    unless (@git_status) {
        system("git status");
        exit;
    }

    # set @parsed_git_status
    parse_git_status();

    if ($list) {
        foreach my $line (@parsed_git_status) {
            my ($status, $file_path) = get_status_and_path($line);
            if ($status eq $ADDED_STATUS) { next }
            print $file_path . "\n";
        }
        exit;
    }

    my $git_message =
        $ARGV[0] || $ENV{GACP_DEFAULT_MESSAGE} || "updated README";

    update_dirs_to_add();
    update_dirs_to_exclude();

    unless (@files_to_add) { $files_to_add[0] = "-A" }

    my ($added_files_info, $excluded_files_info) = get_info();

    my @added_files = ();
    if (@$added_files_info) {
        my $total = scalar(@$added_files_info);
        $MAX_TOTAL = max($MAX_TOTAL, $total);
        print colored(get_heading("Added", $total) . "\n", $DOC_COLOR);
        while (my ($i, $elem) = each @$added_files_info) {
            print_file($i + 1, $elem->[0], $elem->[1]);
            push(@added_files, $elem->[1]);
        }
        print "\n";
    }

    if (@$excluded_files_info) {
        my $total = scalar(@$excluded_files_info);
        $MAX_TOTAL = max($MAX_TOTAL, $total);
        print colored(get_heading("Excluded", $total) . "\n", $DOC_COLOR);
        while (my ($i, $elem) = each @$excluded_files_info) {
            print_file($i + 1, $elem->[0], $elem->[1], $EXC_COLOR);
        }
        print "\n";
    }

    print colored("Commit message:\n", $DOC_COLOR);
    print colored("    $git_message\n\n", $STR_COLOR);

    if ($dry_run) { exit; }

    unless (@$added_files_info) {
        print "Nothing added\n";
        exit;
    }

    # git add, commit and push
    my $joined_added_files = join(" ", @added_files);
    my $git_add_command    = "git add " . $joined_added_files;
    my $git_commit_command = "git commit -m '" . $git_message . "'";
    my $git_push_command   = "git push";

    my $prev_return = system($git_add_command);
    if ($prev_return eq "0") {
        $prev_return = system($git_commit_command);
    }
    if ($prev_return eq "0" && !$dont_push) {
        system($git_push_command);
    }
}


# # Helper func for debugging (can be commented out)
# sub debug_print {
#     my ($text, $color) = @_;
#     unless ($color) { $color = $STR_COLOR }
#     print colored($text, $color) . "\n";
# }

main()
