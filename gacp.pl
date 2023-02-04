#!/usr/bin/env perl

# wrapper around git-add-commit-push

use strict;
use Term::ANSIColor;
use Getopt::Long;

my @files_to_add     = ();
my @files_to_exclude = ();
my $dry_run;
my $help;
# these files will be git added # (@files_to_add - @files_to_exclude)
my @added_files = ();

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

sub print_files_to_add {
    print "Added files:\n";

    # parse git status porcelain
    my $git_status = `git status --porcelain`;

    foreach my $line (split "\n", $git_status) {
        my ($status, $file_name) = split " ", $line;

        if (grep /^[.\/]*$file_name$/, @files_to_exclude) { next };
        if (@files_to_add[0] ne "-A" && !(grep /^$file_name$/, @files_to_add)) {
            next
        }

        if ($status eq "??") {
            print colored("\t$file_name\t(new)", $NEW_COLOR) . "\n";
        } elsif ($status eq "D") {
            print colored("\t$file_name\t(deleted)", $DEL_COLOR) . "\n";
        } elsif ($status eq "M") {
            print colored("\t$file_name\t(modified)", $MOD_COLOR) . "\n";
        }

        push(@added_files, $file_name);
    }
    print "\n";
}

sub print_files_to_exclude {
    print "Excluded files:\n\t";
    print colored(join("\n\t", @files_to_exclude), $EXC_COLOR) . "\n";
    print "\n";
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

    unless (`git rev-parse --is-inside-work-tree` eq "true\n") {
        print "Not a git repository";
        return;
    }

    unless (`git status --porcelain`) {
        system("git status");
        return;
    }

unless (@files_to_add) { $files_to_add[0] = "-A" }
    unless (@files_to_add[0] eq @files_to_exclude[0]) { print_files_to_add() }

    if (scalar(@files_to_exclude) > 0) { print_files_to_exclude() }

    my $git_message = $ARGV[0] || "updated README";

    if ($dry_run) {
        print "git add " . join(" ", @added_files) . "\n";
        print "git commit -m \"$git_message\" \n";
        print "git push\n";
    } else {
        system("git add " . join(" ", @added_files));
        system("git commit -m \"$git_message\"");
        system("git push");
    }
}

main()
