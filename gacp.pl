#!/usr/bin/env perl

# wrapper around git-add-commit-push

use strict;
use Term::ANSIColor;
use File::Spec::Functions qw(abs2rel);
use File::Basename qw(fileparse);
use Getopt::Long;

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
        format_option("e", "exclude", "Files to exclude (not commit)", 1, 0),
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

sub print_file {
    my ($status, $file_name) = @_;

    if ($status eq "??") {
        printf(
            "\t%-25s %s\n",
            colored("$file_name", $NEW_COLOR), colored("(new)", $NEW_COLOR)
            )
    } elsif ($status eq "D") {
        printf(
            "\t%-25s %s\n",
            colored("$file_name", $DEL_COLOR), colored("(deleted)", $DEL_COLOR)
            )
    } elsif ($status eq "M") {
        printf(
            "\t%-25s %s\n",
            colored("$file_name", $MOD_COLOR), colored("(modified)", $MOD_COLOR)
            )
    }
}

sub print_files_to_exclude {
    print "Excluded files:\n\t";
    print colored(join("\n\t", @files_to_exclude), $EXC_COLOR) . "\n\n";
}


sub get_added_files_and_status {
    # these files will be git added # (@files_to_add - @files_to_exclude)
    my @added_files_and_status = ();


    # parse git status porcelain
    my $git_status = `git status --porcelain`;

    foreach my $line (split "\n", $git_status) {
        my ($status, $file_name) = split " ", $line;

        my $top_level = `git rev-parse --show-toplevel`;
        my ($repo_dir) = fileparse($top_level);
        my $rel_path = abs2rel($top_level);

        $rel_path =~ s/\.\.\/$repo_dir//;

        if (grep /^[.\/]*$file_name$/, @files_to_exclude) { next };
        if (@files_to_add[0] ne "-A" && !(grep /^$file_name$/, @files_to_add)) {
            next
        }

        push(@added_files_and_status, [$status, $file_name]);
    }

    return @added_files_and_status;
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

    my @added_files_and_status = get_added_files_and_status();
    my @added_files = ();

    if (scalar(@added_files_and_status) > 0) {
        print "Added files:\n";
        for (@added_files_and_status) {
            print_file($_->[0], $_->[1]);
            push(@added_files, $_->[1]);
        }
        print "\n";
    }

    unless(scalar(@added_files)) {
        print "Nothing added\n";
        return;
    }
    if (scalar(@files_to_exclude) > 0) { print_files_to_exclude() }

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
