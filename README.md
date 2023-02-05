# gacp
git add, commit and push in one go.

## About
gacp is a wrapper around `git` to make commiting and pushing files convenient.

## Usage
```text
USAGE:
	gacp [ARGS] [OPTIONS]

OPTIONS:
	h, --help 		Print help information
	d, --dry 		Dry-run (show what will happen)
	f, --files <FILES>	Files to add (git add) [default: -A]
	e, --exclude <EXCLUDE>	Files to exclude (not commit)

ARGS:
	<MESSAGE> 		Commit message [default: "updated README"]
EXAMPLE:
	gacp "First Commit"
	gacp "updated README" -f README.md
	gacp "Pushing all except new-file.pl" -e new-file.pl
```

## Examples
```text
$ gacp "First Commit" -dry
Added files:
	gacp.pl	(new)

git add gacp.pl
git commit -m "First Commit"
git push
```

```text
$ gacp "pushing all" -dry
Added files:
	gacp.pl 	(modified)
	README.md	(new)

git add -A
git commit -m "pushing all"
git push
```