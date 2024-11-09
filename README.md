A drop-in replacement for the original Zig Language Server, with several enhancements to improve development experience.

Key differences:
- Reworked Modules Collection and Lookup ([How to set/switch `root_id`](https://github.com/llogick/zigscient/wiki/Modules:-Switching-%60root_id%60))
- Modified Parser
  - Slightly better syntax errors handling
  - Faster reparsing for large documents
- Declaration Literals completions/hover/goto def
- Completions for errors and fn returns, eg:
  - `return .`
  - `return error.`
  - `switch(err) { error. }`

> [!NOTE]  
> Remember to rename the executable or update your editor's configuration
