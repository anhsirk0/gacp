# gacp
git add, commit and push in one go.

## About
gacp is a wrapper around `git` to make commiting and pushing files convenient.

## Usage
```text
gacp
git add, commit & push in one go.

USAGE:
	gacp [ARGS] [OPTIONS]

OPTIONS:
	h, --help 		Print help information
	l, --list 		List new/modified/deleted files
	d, --dry 		Dry-run (show what will happen)
	ni, --no-ignore 	Don't auto exclude files specified in gacp ignore file
	f, --files <FILES>	Files to add (git add) [default: -A]
	e, --exclude <EXCLUDE>	Files to exclude (not to add)

ARGS:
	<MESSAGE> 		Commit message [default: "updated README"]
EXAMPLE:
	gacp "First Commit"
	gacp "updated README" -f README.md
	gacp "Pushing all except new-file.pl" -e new-file.pl
```

## Configurations
To change default git message add $GACP_DEFAULT_MESSAGE var to environment
```shell
export GACP_DEFAULT_MESSAGE="My default git commit message"
```

To add files to exclude automatically (like .gitignore), create `~/.config/gacp/repo_name.ignore` file  
Example: to always exclude `src/environment.ts` from repo `react-app`  
Create file `~/.config/gacp/react-app.ignore` with contents
```text
src/environment.ts
# any number of files can be added here
```
you can provide `--no-ignore` or `-ni` flag if you want to add and commit these files

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

## List & Completions
`gacp` provides `--list`, `-l` flag, which will list new/modified/deleted files  
This output can be used as completions for `gacp`  
```text
$ gacp --list
gacp.pl
README.md
```

If you are a fish user you can add completions like this  
Create a file `/$HOME/.config/fish/completions/gacp.fish` with following content
```shell
complete -f -c gacp -a "(gacp --list)"
```
