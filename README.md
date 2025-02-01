A drop-in alternative to the original Zig Language Server, with several enhancements.

Key features and improvements:
- Reworked Modules Collection and Lookup
  - Modules are grouped by CompileStep (root ID). See [How to set/switch `root_id`](https://github.com/llogick/zigscient/wiki/Modules:-Switching-%60root_id%60)
- Improved parser performance:
  - Slightly better syntax error handling
  - Faster reparsing of large documents
- Enhanced code completions:
  - Declaration literals: autocompletion and navigation support
  - Error and function return type completions, e.g. `return .`, `return error.`, and `switch(err) { error. }`


> [!NOTE]  
> Remember to rename the executable or update your editor's configuration
