# Manual steps after setup

These logins need a browser or credentials, so they are done by hand the
first time each is needed.

## Azure

```
az login
```

## Container registry

Replace <registry> with your registry name.

```
az acr login --name <registry>
```

## Claude Code

Start it once and follow the login prompt.

```
claude
```

## Terminal font (WSL)

The Code New Roman Nerd Font is installed inside Linux, but Windows
Terminal renders on the Windows side. Install the font on Windows too
(download CodeNewRoman.zip from the ryanoasis/nerd-fonts releases) and
select "CodeNewRoman Nerd Font" in the Windows Terminal profile.
