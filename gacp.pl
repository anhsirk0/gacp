#!/usr/bin/env perl

# git add, commit and push in one go.
# https://codeberg.org/anhsirk0/gacp

use strict;
use Term::ANSIColor;
use File::Spec::Functions qw(abs2rel);
use File::Basename qw(fileparse);
use Cwd qw(getcwd);
use Getopt::Long;

# for cli args
my @files_to_add     = ();
my @files_to_exclude = ();
my $dry_run;
my $help;

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
        "%s\n%s\n\n%s\n%s\n\n%s \n%s%s%s%s \n%s\n%s %s\n%s\n%s\n%s %s\n%s %s\n",
        colored("gacp", "green"),
        "git add, commit and push in one go.",
        colored("USAGE:", "yellow"),
        "\tgacp [ARGS] [OPTIONS]",
        colored("OPTIONS:", "yellow"),
        format_option("h", "help", "Print help information", 0, 0),
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

    if ($status eq "??") {
        $color = $color || $NEW_COLOR;
        printf(
            "\t%-40s %s\n",
            colored("$file_name", $color), colored("(new)", $color)
            )
    } elsif ($status eq "D") {
        $color = $color || $DEL_COLOR;
        printf(
            "\t%-40s %s\n",
            colored("$file_name", $color), colored("(deleted)", $color)
            )
    } elsif ($status eq "M") {
        $color = $color || $MOD_COLOR;
        printf(
            "\t%-40s %s\n",
            colored("$file_name", $color), colored("(modified)", $color)
            )
    }
}

# get paths relative to top-level (root) of the git repository
# Params:
#    files   (array of file_names : Array<String>)
# Returns:
#    files_path   (array of file_names : Array<String>)
# Example:
# ["some-file.pl"] -> ["src/lib/some-file.pl"]
sub get_top_level_rel_path {
    my @files = @_;
    my @file_paths = ();
    foreach my $f (@files) {
        chomp(my $top_level = `git rev-parse --show-toplevel`);
        my ($repo_dir) = fileparse($top_level);
        my $top_level_rel_path = abs2rel(getcwd() . "/" . $f, $top_level);
        $top_level_rel_path =~ s/\.\.\/$repo_dir//;
        push(@file_paths, $top_level_rel_path);
    }

    return @file_paths;
}

# Return reference to 2 arrays containing info about added & excluded files
# after parsing `git status --porcelain`
# Params:
#    ref_files_to_add      (reference to files_to_add array)
#    ref_files_to_exclude
# Example:
#    `git status --porcelain` = ?? new-file.pl, M mod-file.pl, D del-file.pl
#    @files_to_add = ["mod-file.pl", "del-file.pl"]
#    @files_to_exclude = ["new-file.pl"]
#    will return =>
#    @files_to_add = [["M", "mod-file.pl"], ["D", "del-file.pl"]]
#    @files_to_exclude = [["??", "new-file.pl"]]
sub get_info (\@\@) {
    my ($ref_files_to_add, $ref_files_to_exclude) = @_;
    # these files will be git added # (@files_to_add - @files_to_exclude)
    my @added_files_info = ();
    my @excluded_files_info = ();


    # parse git status porcelain
    my $git_status = `git status --porcelain`;

    foreach my $line (split "\n", $git_status) {
        my ($status, $file_name) = split " ", $line;
        if (grep /^$file_name$/, @{$ref_files_to_exclude}) {
            push(@excluded_files_info, [$status, $file_name]);
            next;
        };
        if (
            @files_to_add[0] ne "-A" &&
            !(grep /^$file_name$/, @{$ref_files_to_add})
            ) {
            next
        }
        push(@added_files_info, [$status, $file_name]);
    }

    return (\@added_files_info, \@excluded_files_info);
}

sub main {
    GetOptions (
        "help|h" => \$help,
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

    # If nothing to commit
    unless (`git status --porcelain`) {
        system("git status");
        return;
    }
    my $git_message = $ARGV[0] || "updated README";

    unless (@files_to_add) { $files_to_add[0] = "-A" }
    my @parsed_files_to_add = get_top_level_rel_path(@files_to_add);
    my @parsed_files_to_exclude = get_top_level_rel_path(@files_to_exclude);

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
        return;
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
        if ($prev_return eq "0") {
            $prev_return = system("git commit -m \"$git_message\"");
        }
        if ($prev_return eq "0") {
            system("git push");
        }
    }
}

main()
