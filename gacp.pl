#!/usr/bin/env perl

# git add, commit and push in one go.
# https://codeberg.org/anhsirk0/gacp

use strict;
use Term::ANSIColor;
use File::Spec::Functions qw(abs2rel);
use File::Basename qw(fileparse);
use File::Find;
use Cwd qw(getcwd);
use Getopt::Long;

# for cli args
my @files_to_add     = ();
my @files_to_exclude = ();
my $dry_run;
my $help;
my $list;

# This tool relies on `git status --porcelain`
# For convenience, `git status --porcelain` is referred as git_status
my $git_status;
my @parsed_git_status;
my @files_inside_new_dir = ();
my $top_level;

my $COLS = 72;

# color constants
my $MOD_COLOR = "bright_green"; # for modified files
my $DEL_COLOR = "bright_red";   # for deleted files
my $NEW_COLOR = "bright_cyan";  # for newly created files
my $EXC_COLOR = "yellow";       # for excluded files
my $STR_COLOR = "bright_blue";  # for string args


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
    my $text = "\t" . colored($short, "green");
    $text .= ", " . colored("--" . $long . " ", "green");
    $text .= ($args ? colored("<" . uc $long . ">", "green") . "\t" : "\t\t");
    $text .= $desc . ($default ? " [default: " . $default . "]" : "");
    return $text . "\n";
}


sub print_help {
    # This is a mess
    printf(
        "%s\n\n%s\n\n%s \n%s%s%s%s%s \n%s\n%s %s\n%s\n%s\n%s %s\n%s %s\n",
        colored("gacp", "green") . "\n" . "git add, commit & push in one go.",
        colored("USAGE:", "yellow") . "\n\t" . "gacp [ARGS] [OPTIONS]",
        colored("OPTIONS:", "yellow"),
        format_option("h", "help", "Print help information", 0, 0),
        format_option("l", "list", "List new/modified/deleted files", 0, 0),
        format_option("d", "dry", "Dry-run (show what will happen)", 0, 0),
        format_option("f", "files", "Files to add (git add)", 1, "-A"),
        format_option("e", "exclude", "Files to exclude (not to add)", 1, 0),
        colored("ARGS:", "yellow"),
        colored("\t<MESSAGE>", "green"),
        "\t\tCommit message [default: \"updated README\"]",
        colored("EXAMPLE:", "yellow"),
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
    my ($status, $file_name, $color) = @_;
    my $available_cols = `tput cols`;
    # if `tput cols` return non-zero exit status code
    if ($?) { $available_cols = 60; }
    $available_cols = int($available_cols);

    if ($COLS + 8 > $available_cols) { $COLS = $available_cols; }

    if ($status eq "??") {
        $color = $color || $NEW_COLOR;
        printf(
            "    %-" . $COLS . "s %s\n",
            colored("$file_name", $color), colored("(new)", $color)
            )
    } elsif ($status eq "D") {
        $color = $color || $DEL_COLOR;
        printf(
            "    %-" . $COLS . "s %s\n",
            colored("$file_name", $color), colored("(deleted)", $color)
            )
    } elsif ($status eq "M") {
        $color = $color || $MOD_COLOR;
        printf(
            "    %-" . $COLS . "s %s\n",
            colored("$file_name", $color), colored("(modified)", $color)
            )
    }
}


# wanted sub for finding files
sub wanted {
    my $file_name = $File::Find::name;
    # my $file = (split "/", $file_name)[-1];

    # TODO : Check through .gitignore for files
    # if ($in_gitignore) { return }

    if (-f) {
        push(@files_inside_new_dir, $file_name)
    }
}


# Print $git_status but relative path to current dir
# Can be used for completions
sub parse_git_status {
    foreach my $line (split("\n", $git_status)) {
        my ($status, $file_path) = split(" ", $line);
        my $rel_path = abs2rel($top_level . "/" . $file_path);

        # if a directory is newly created
        # git_status only lists the directory and not the files inside
        if (-d $rel_path) {
            find({
                wanted => \&wanted,
                 }, $rel_path);
        }
        if (@files_inside_new_dir) {
            foreach my $f (@files_inside_new_dir) {
                my ($file_basename, $parent) = fileparse($f);
                my ($current_dir_basename) = fileparse(getcwd());
                if ($parent =~ /$current_dir_basename\/$/ || $parent eq "./") {
                    $f =~ s/^$parent//;
                } else {
                    $f =~ s/$rel_path\//:\/:$file_path/;
                }
                push(@parsed_git_status, $status . " " . $f);
            }
            next;
        }

        if ($rel_path =~ /^\.\.\//) {
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
            !(grep /^$file_path$/, @{$ref_files_to_add})
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
    chomp($git_status = `git status --porcelain`);

    # If nothing to commit
    unless ($git_status) {
        system("git status");
        exit;
    }

    # set @parsed_git_status
    parse_git_status();

    if ($list) {
        foreach my $f (@parsed_git_status) {
            print $f . "\n";
        }
        exit;
    }

    my $git_message = $ARGV[0] || "updated README";

    unless (@files_to_add) { $files_to_add[0] = "-A" }
    my @parsed_files_to_add = @files_to_add;
    my @parsed_files_to_exclude = @files_to_exclude;

    for(@parsed_files_to_add) {
        print colored($_, $DEL_COLOR) . "\n";
    }

    my ($added_files_info, $excluded_files_info) = get_info(
        @parsed_files_to_add,
        @parsed_files_to_exclude
        );

    my @added_files = ();
    if (scalar(@$added_files_info)) {
        print "Added files:\n";
        for (@$added_files_info) {
            print_file($_->[0], $_->[1]);
            push(@added_files, $_->[1]);
        }
        print "\n";
    } else {
        print "Nothing added\n";
        exit;
    }

    if (scalar(@$excluded_files_info) > 0) {
        print "Excluded files:\n";
        for (@$excluded_files_info) {
            print_file($_->[0], $_->[1], $EXC_COLOR);
        }
        print "\n";
    }

    if ($dry_run) {
        print "git add " . join(" ", @added_files) . "\n";
        print "git commit -m \"$git_message\" \n";
        print "git push\n";
    } else {
        my $prev_return = system("git add " . join(" ", @added_files));
        # if ($prev_return eq "0") {
        #     $prev_return = system("git commit -m \"$git_message\"");
        # }
        # if ($prev_return eq "0") {
        #     system("git push");
        # }
    }
}

main()
