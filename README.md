# gacp
git add, commit and push in one go.

+ Git repo on Codeberg: <https://codeberg.org/anhsirk0/gacp>
  - Mirrors:
    + GitHub: <https://github.com/anhsirk0/gacp>

## About
gacp is a wrapper around `git` to make commiting and pushing files convenient.
> works only on unix-like systems (Linux, BSD, MacOS)

## Screenshot
![screenshot.png](https://codeberg.org/anhsirk0/gacp/raw/branch/main/screenshot.png)

## Installation
Its just a perl script
download it make it executable and put somewhere in your $PATH

#### with wget
``` bash
wget https://codeberg.org/anhsirk0/gacp/raw/branch/main/gacp.pl -O gacp
```
#### or with curl
``` bash
curl https://codeberg.org/anhsirk0/gacp/raw/branch/main/gacp.pl --output gacp
```
#### making it executable
```bash
chmod +x gacp
```
#### copying it to somewhere in $PATH
```bash
cp gacp ~/.local/bin/
```
or 
```bash
sudo cp gacp /usr/local/bin/    # root required
```

## Usage
```text
USAGE:
	gacp [ARGS] [OPTIONS]

OPTIONS:
	h, --help 		Print help information
	l, --list 		List new/modified/deleted files
	d, --dry 		Dry-run (show what will happen)
	r, --relative-paths 	Enable Relative paths
	ni, --no-ignore 	Don't auto exclude files specified in gacp ignore file
	np, --no-push 		No push (Only add and commit)
	f, --files <FILES>	Files to add (git add) [default: -A]
	e, --exclude <EXCLUDE>	Files to exclude (not to add)

ARGS:
	<MESSAGE> 		Commit message
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

### Auto Exclude files via gacp exclude file
To add files to exclude automatically (like .gitignore), create `~/.config/gacp/gacp.exclude` file  

Example:
```text
# Repo's absolute path           =  comma separated files/dirs
/home/user/projects/some-project = src/environment.ts, new-dir, some-dir/new
# any number of files can be added here
```
you can provide `--no-ignore` or `-ni` flag if you want to add and commit these files

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

## Examples

```text
$ gacp -dry
Added files:
	gacp.pl	(new)
```

```text
$ gacp "First Commit" -dry
Added files:
	gacp.pl	(new)

Commit Message:
	First Commit
```

```text
$ gacp -f README.md -dry
Added files:
	README.md	(new)
```

```text
$ gacp "Pushing all files except README" -e README.md -dry
Added files:
	gacp.pl	(modified)

Excluded files:
	README.md	(new)

Commit Message:
	Pushing all files except README
```

## Supported ways to add/exclude files
```text
gacp -f ../some-file.pl
```
```text
gacp -f ../some-file.pl
```
```text
gacp -f :/:src/some-file.pl
```
```text
gacp -f ./some-file.pl
```
```text
gacp -f some-file.pl
```
```text
gacp -f ./dir/some-file.pl
```
```text
gacp -f dir/some-file.pl
```

