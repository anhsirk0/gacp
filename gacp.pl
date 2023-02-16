#!/usr/bin/env perl

# git add, commit and push in one go.
# https://codeberg.org/anhsirk0/gacp

use strict;
use Cwd qw(getcwd);
use File::Basename qw(fileparse);
use File::Find;
use File::Spec::Functions qw(abs2rel);
use Getopt::Long;
use Term::ANSIColor;

# for cli args
my @files_to_add     = ();
my @files_to_exclude = ();
my $dry_run;
my $help;
my $list;
my $dont_ignore;

# This tool relies on `git status --porcelain`
# For convenience, `git status --porcelain` is referred as git_status
my @git_status;
my @parsed_git_status;
my @files_inside_new_dirs = ();
my $top_level;

my $COLS = 72;
my $CONFIG_DIR = $ENV{HOME} . "/.config/gacp";

# color constants
my $GREEN     = "bright_green";
my $YELLOW    = "yellow";
my $MOD_COLOR = $GREEN;        # for modified files
my $DEL_COLOR = "bright_red";  # for deleted files
my $NEW_COLOR = "cyan";        # for newly created files
my $EXC_COLOR = $YELLOW;       # for excluded files
my $STR_COLOR = "bright_blue"; # for string args
my $DOC_COLOR = "bright_black";


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
    my $tab_chars = "\t" . (length($short . $long . $long x $args) < 11 && "\t");
    my $text = "\t" . colored($short, $GREEN);
    $text .= ", " . colored("--" . $long . " ", $GREEN);
    $text .= ($args > 0 && colored("<" . uc $long . ">", $GREEN)) . $tab_chars;
    $text .= $desc . ($default ne 0 && " [default: " . $default . "]");
    return $text . "\n";
}


sub print_help {
    # This is a mess
    printf(
        "%s\n\n%s\n\n%s \n%s%s%s%s%s%s \n%s\n%s %s\n%s\n%s\n%s %s\n%s %s\n",
        colored("gacp", $GREEN) . "\n" . "git add, commit & push in one go.",
        colored("USAGE:", $YELLOW) . "\n\t" . "gacp [ARGS] [OPTIONS]",
        colored("OPTIONS:", $YELLOW),
        format_option("h", "help", "Print help information", 0, 0),
        format_option("l", "list", "List new/modified/deleted files", 0, 0),
        format_option("d", "dry", "Dry-run (show what will happen)", 0, 0),
        format_option(
            "ni", "no-ignore",
            "Don't auto exclude files specified in gacp ignore file",
            0, 0
        ),
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
#     status     (Status of the file : "??" | "M" | "D")
#     file_name  (Name of the file : String)
# Example print:
#     modified_file.pl     (modified)
#     newly_created.pl     (new)
#     deleted_file.pl      (deleted)
sub print_file {
    my ($idx, $status, $file_name, $color) = @_;
    my $available_cols = `tput cols`;
    # if `tput cols` return non-zero exit status code
    if ($?) { $available_cols = $COLS; }
    $available_cols = int($available_cols);

    if ($COLS + 8 > $available_cols) { $COLS = $available_cols; }

    my $label;
    if ($status eq "??") {
        $color = $color || $NEW_COLOR;
        $label = "new";
    } elsif ($status eq "D") {
        $color = $color || $DEL_COLOR;
        $label = "delete";
    } elsif ($status eq "M") {
        $color = $color || $MOD_COLOR;
        $label = "modified";
    }
    printf(
        "    %-" . $COLS . "s %s\n",
        colored("$idx\) $file_name", $color), colored("($label)", $color)
        );
}


sub get_heading {
    my ($name, $total) = @_;
    return "$name ($total file" . ($total > 1 && "s") . "):";
}


# Read $CONFIG_DIR/repo.ignore and return ignored files
sub get_ignored_files {
    my @ignored_files = ();
    my ($repo) = fileparse($top_level);
    my $ignore_file = $CONFIG_DIR . "/" . $repo . ".ignore";
    unless (-f $ignore_file) { return }
    open(FH, "<" . $ignore_file) or die "Unable to open $ignore_file";
    while(<FH>) {
        for ($_) {
            s/\#.*//; # ignore comments
            s/\s+/ /g; # remove extra whitespace
            s/^\s+//g; # strip left whitespace
            s/\s+$//g; # strip right whitespace
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

    if (-f) {
        push(@files_inside_new_dirs, $file_name)
    }
}


# Print $git_status but relative path to current dir
# Can be used for completions
sub parse_git_status {
    # Read ignore file
    my @ignored_files = ();
    unless ($dont_ignore) {
        @ignored_files = get_ignored_files();
    }

    foreach my $line (@git_status) {
        my ($status, $file_path) = split(" ", $line);
        my $rel_path = abs2rel($top_level . "/" . $file_path);

        if (@ignored_files) {
            my $rgx = qr/^${file_path}$/;
            if (-d $rel_path) {
                my $dir = abs2rel(getcwd(), $top_level);
                unless ($dir eq ".") {
                    $rgx = qr/^${dir}/;
                }
            }

            if (grep /$rgx/, @ignored_files) {
                unless ($file_path eq $rel_path) {
                    $file_path = ":/:" . $file_path;
                }
                push(@files_to_exclude, $file_path);
                push(@parsed_git_status, $status . " " . $file_path);
                next;
            }
        }

        # if a directory is newly created
        # git_status only lists the directory and not the files inside
        if (-d $rel_path) {
            find({
                wanted => \&wanted,
                 }, $rel_path);
        }
        if (@files_inside_new_dirs) {
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
                } else {
                    $f =~ s/$rel_path\//:\/:$file_path/;
                }
                push(@parsed_git_status, $status . " " . $f);
            }
            next;
        }

        if ($rel_path =~ m/^\.\.\//) {
            $rel_path = ":/:" . $file_path;
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
sub get_info (\@\@) {
    my ($ref_files_to_add, $ref_files_to_exclude) = @_;
    # these files will be git added # (@files_to_add - @files_to_exclude)
    my @added_files_info = ();
    my @excluded_files_info = ();

    my $max_width = 1;

    foreach my $line (@parsed_git_status) {
        my ($status, $file_path) = split(" ", $line);
        if (length($file_path) + 14 > $max_width) {
            $max_width = length($file_path) + 14;
        }
        if (grep /^$file_path$/, @{$ref_files_to_exclude}) {
            push(@excluded_files_info, [$status, $file_path]);
            next;
        };
        if (
            @files_to_add[0] ne "-A" &&
            !(grep /^(\.\/)?$file_path$/, @{$ref_files_to_add})
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
        "no-ignore|ni" => \$dont_ignore,
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
            my ($status, $file_path) = split(" ", $line);
            print $file_path . "\n";
        }
        exit;
    }

    my $git_message =
        $ARGV[0] || $ENV{GACP_DEFAULT_MESSAGE} || "updated README";

    unless (@files_to_add) { $files_to_add[0] = "-A" }

    my ($added_files_info, $excluded_files_info) = get_info(
        @files_to_add,
        @files_to_exclude
        );

    my @added_files = ();
    if (@$added_files_info) {
        my $total = scalar(@$added_files_info);
        print colored(get_heading("Added", $total) . "\n", $DOC_COLOR);

        while (my ($i, $elem) = each @$added_files_info) {
            print_file($i + 1, $elem->[0], $elem->[1]);
        }
        print "\n";
    }

    if (@$excluded_files_info) {
        my $total = scalar(@$excluded_files_info);
        print colored(get_heading("Exclude", $total) . "\n", $DOC_COLOR);
        while (my ($i, $elem) = each @$excluded_files_info) {
            print_file($i + 1, $elem->[0], $elem->[1], $EXC_COLOR);
        }
        print "\n";
    }

    unless (@$added_files_info) {
        print "Nothing added\n";
        exit;
    }

    # my $joined_added_files = $files_to_add[0] eq "-A" ?
    #     "-A" :
    #     join(" ", @added_files);
    my $joined_added_files = join(" ", @added_files);

    my $git_add_command    = "git add " . $joined_added_files;
    my $git_commit_command = "git commit -m \"$git_message\"";
    my $git_push_command   = "git push";

    if ($dry_run) {
        print $git_add_command . "\n";
        print $git_commit_command . "\n";
        print $git_push_command . "\n";
    } else {
        my $prev_return = system($git_add_command);
        if ($prev_return eq "0") {
            $prev_return = system($git_commit_command);
        }
        if ($prev_return eq "0") {
            system($git_push_command);
        }
    }
}


main()
