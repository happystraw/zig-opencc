# Zig OpenCC

[OpenCC](https://github.com/BYVoid/OpenCC) 的 Zig 封装，提供中文简繁转换功能。

本项目既可以作为**交叉构建工具**来构建 OpenCC 静态库和工具，也可以作为 **Zig 库**直接在 Zig 项目中使用。

## 系统要求

- Zig: 0.15.2

## 使用说明

### 作为交叉构建工具

快速开始：

```bash
zig build -Doptimize=ReleaseFast
```

更多使用说明：

```bash
# 查看构建选项
zig build --help

# 构建所有内容
zig build
zig build -Doptimize=ReleaseFast --prefix=/usr/local/

# 仅构建库
zig build lib
# 仅构建执行程序（opencc, opencc_dict, opencc_phrase_extract）
zig build exe
# 仅构建和生成字典文件
zig build dict

# 交叉编译到其他平台
zig build -Dtarget=x86_64-windows
zig build -Dtarget=aarch64-macos
zig build -Dtarget=aarch64-linux-musl

# 发布版本构建
zig build -Doptimize=ReleaseFast
```

### 作为 Zig 库

添加依赖

在 `build.zig.zon` 中：

```bash
zig fetch --save=opencc git+https://github.com/happystraw/zig-opencc
```

配置 build.zig

```zig
const opencc_dep = b.dependency("opencc", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("opencc", opencc_dep.module("opencc"));
```

使用示例

```zig
pub fn main() !void {
    const opencc: *OpenCC = try .init("/path/to/s2twp.json");
    defer opencc.deinit();

    const input = "网络鼠标键盘";
    const output = try opencc.convert(input);
    defer opencc.free(output);

    std.debug.print("{s}\n", .{output});
    // Output: 網路滑鼠鍵盤
}

const std = @import("std");
const OpenCC = @import("opencc").OpenCC;
```
