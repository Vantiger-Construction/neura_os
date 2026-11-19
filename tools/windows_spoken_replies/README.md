# Windows spoken replies launcher

Open `START_NEURA.exe` beside the extracted `Windows` folder to enable spoken
replies each time you start Neura. The launcher uses the current Windows
user's saved voice settings. A saved streaming voice stays enabled and a muted
Neura volume returns to 70%. Microphone and startup greeting preferences are
independent. [Instructions for using the package](START_HERE.txt).

## Build the reviewed package

The Windows spoken replies launcher workflow tests the native preference writer
and produces a downloadable ZIP. It packages the Windows app from the November
19 build review. [Reviewed Windows release](https://github.com/Vantiger-Construction/neura_os/releases/tag/neura-ci-pr-234-881da717d74b-4c74e6237c11).

To build locally, use Windows x64, Go 1.27.4 and Python 3.11 or later. In this
directory, save the Windows ZIP from that release as `neura-base.zip` and run
the following in PowerShell.

```powershell
$env:CGO_ENABLED = '0'
go test -mod=readonly ./...
go build -mod=readonly -trimpath -buildvcs=false -ldflags='-s -w -H=windowsgui' -o START_NEURA.exe .
python package.py neura-base.zip START_NEURA.exe Neura-Windows-Spoken-Replies.zip
```

The packager verifies the original Windows ZIP's SHA-256 before copying its
contents. The launcher tests use synthetic preferences. To check playback,
open the package on a Windows PC and send a message in ordinary chat.
