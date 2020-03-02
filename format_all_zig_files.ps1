ForEach ($item in (Get-ChildItem -Recurse *.zig)) {
    zig fmt $item.FullName;
}
