# PreviewDocs

PreviewDocs is a lightweight native macOS file previewer for development work.
It opens Markdown, HTML, source files, PDFs, and images in a fast AppKit/WebKit
viewer without requiring an Xcode project.

## Features

- Markdown preview with `Preview / Source` switching
- HTML, PDF, and image preview through WebKit
- Source and data files displayed as plain monospaced text
- Multiple files open as macOS window tabs
- Open dialog shows dotfiles and hidden folders
- Right sidebar file tree rooted at your home folder, with lazy folder loading
- Sidebar actions for creating files/folders, renaming items, editing ignore rules, and opening files in the current preview or a new tab
- UTF-8 text editing with explicit save and unsaved-change prompts
- Toolbar actions for copying the file path, copying text contents, revealing in Finder, and refreshing
- Light and dark mode styling for rendered Markdown and text views
- File type registration through the app bundle `Info.plist`

## Supported Files

| Type | Extensions | Rendering |
| --- | --- | --- |
| Markdown | `.md`, `.markdown`, `.mdown`, `.mkd` | `marked.min.js` to HTML |
| HTML | `.html`, `.htm` | Native `WKWebView` |
| PDF | `.pdf` | Native `WKWebView` |
| Images | `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.svg`, `.bmp`, `.tif`, `.tiff`, `.heic`, `.heif`, `.ico` | Native `WKWebView` |
| Text / code / data | `.txt`, `.json`, `.yaml`, `.swift`, `.py`, `.log`, and similar | Plain text |

## Requirements

- macOS
- Xcode Command Line Tools
- Apple Silicon Mac, based on the current `arm64-apple-macos14.0` build target

## Build

```bash
./build.sh
```

The build script creates `PreviewDocs.app` in the project root.
If `Resources/marked.min.js` is missing, the script downloads it from jsDelivr.

## Run

Open the app directly:

```bash
open PreviewDocs.app
```

Open files from the command line:

```bash
open -n -a PreviewDocs.app README.md
open -n -a PreviewDocs.app file.md file.pdf image.png
```

When multiple files are opened, PreviewDocs adds them as tabs in the same window group.

## Sidebar and Ignore Rules

The right sidebar starts at your home folder and loads folder contents only when
you expand a folder. `Reveal in Tree` switches the sidebar root to the current
file's parent directory. The bottom path bar shows that directory path, and
clicking a directory in the path bar moves the tree root there. Hidden files and
folders are shown, but common heavy folders are excluded by default:

```text
.git
node_modules
.build
DerivedData
.DS_Store
*.app
```

To customize the tree, edit `~/.previewdocs-ignore`. Use one filename or `*`
wildcard pattern per line. Blank lines and lines starting with `#` are ignored.
The sidebar's ignore-rules button creates and opens this file if it does not
exist.

Click a file in the sidebar to open it in the current preview. Option-click a
file to open it as a new tab; the new tab starts with the same sidebar root.
The sidebar toolbar only controls the tree itself: reload tree, new file, new
folder, and ignore rules. Text-readable files are editable in place and must be
saved explicitly.

## Install

```bash
./install.sh
```

This rebuilds `PreviewDocs.app` from the current source, copies it to `/Applications`, and registers the file types with LaunchServices.
After `git pull`, run `./install.sh` again to update the installed app.

To set PreviewDocs as the default app for a file type:

1. Select a file in Finder.
2. Open `Get Info`.
3. Choose `PreviewDocs` under `Open with`.
4. Click `Change All...`.

## Project Layout

```text
Sources/
  main.swift
  AppDelegate.swift
  FileTreeSidebarViewController.swift
  PreviewWindowController.swift
  PreviewViewController.swift
  PreviewWebView.swift
Resources/
  Info.plist
  PreviewDocs.icns
  marked.min.js
build.sh
install.sh
```

## Notes

- Markdown source switching is only shown for Markdown files.
- `Copy Contents` is intended for text-readable files.
- The app is built with `swiftc` directly, not with an Xcode project.
