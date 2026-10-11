<h1 align="center">Zigscient</h1> 
<h3 align="center">A Zig Language Server</h3>
<p align="center">A drop-in alternative to ZLS</p>


## What's different:

- Improved editing responsiveness for large documents
  - Uses an extended parser, that reuses tokens and nodes to process document changes faster

- Improved syntax error handling
  - Uses an extended parser, that works around some common parser deficiencies due to syntax errors

- Reworked Modules Collection and Lookup
  - Modules are grouped by CompileStep (root ID). See [How to set/switch 'root_id'](https://github.com/llogick/zigscient/wiki/Modules:-Switching-%60root_id%60)
  
  (This may look like a step back, but is needed for correct module resolution for modules created using meta-programming that have the same name)

- Propagates error messages originating in currently not-open-in-editor documents based _(0.16.x and earlier)_

    on reference-trace, eg Writers' `print(fmt, args)`

      std.debug.print("{}", .{});      [!] too few arguments
      std.debug.print("", .{1});       [!] unused argument in ''
      std.debug.print("{s}", .{1});    [!] invalid format string ..
      [!] indicates that the error did not originate in the current document/file

- Integrated Incremental Compilation **[Experimental]** _(0.17 +)_

    Performs an incremental compilation update on every document change.

    Does not require saving the document -- uses the in-memory document's data.

    [Basic but important info](https://github.com/llogick/zigscient-next/blob/dev/README.md)

    Zig's incremental compilation is still not fully robust,                                   
    if you find the experience less than optimal set `disable_compilations` to `true`

## [Settings](https://github.com/llogick/zigscient/blob/dev/src/lsp_server/settings.json)

## Building
```bash
ZIG_DEBUG_CMD=1 ZIG_LIB_DIR=./lib zig build -Doptimize=ReleaseFast
```

> [!NOTE]  
> Remember to rename the executable or update your editor's configuration

<br>
<br>

## Disclaimer
This repository contains an independent derivative work that is not affiliated with or endorsed by The Zig Software Foundation.

* **Support & Maintenance:** All technical support, bug tracking, and maintenance are handled exclusively within this repository. Please **file all issues here** and do not submit bugs or requests upstream.
* **Contributor Attribution:** Any attribution of upstream developers in the contributor history or commit log is an artifact of git commit migration. It does not imply their active involvement, endorsement, or support of this specific derivative work.

