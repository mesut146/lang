# x — a Rust-like programming language

`x` is a small self-hosted systems language in the Rust family: structs,
enums, traits, impls, generics, modules, pattern matching (`match`,
`if let`), lambdas, macros, and ownership tracking — compiling through
LLVM 19 to native binaries. The compiler itself is written in `x`.

```rust
func fib(n: i32): i32{
    if(n < 2){
        return n;
    }
    return fib(n - 1) + fib(n - 2);
}

struct Point{ x: i32; y: i32; }

impl Point{
    func origin(): Point{
        return Point{x: 0, y: 0};
    }
}

enum Shape{
    Dot,
    Line{from: Point, to: Point},
}

func main(){
    let p = Point::origin();
    assert(p.x == 0);
    print("hello from x\n");
}
```

## Quick start (prebuilt toolchain)

Toolchains live next to this file (`x-toolchain-<version>-<arch>[/.zip]`,
currently x86_64, aarch64, and Termux-AArch64). Each one carries the
compiler, the C++ bridge library, LLVM, and the standard library sources:

```sh
TC=./x-toolchain-1.05-x86_64
export AR=x86_64-linux-gnu-ar LD=g++
$TC/bin/x c -o hello -out ./out -stdpath $TC/src hello.x
./out/hello
```

Notes:
- `x c` compiles **and runs** the result; pass `-norun` to only build.
- `assert(cond)` is a builtin: failures print `file:line`, the offending
  expression, and the enclosing function. `assert_eq` / `assert2` live in
  `std` for value comparison and custom messages.

## Building from source

Requirements: Linux x86_64, `g++`/`clang++`, `ar`, and LLVM 19
(`bin/llvm.sh` / `bin/apt.sh` fetch it into `build/tmp`).

```sh
bin/stage1.sh <host-toolchain-dir> <version>   # bootstrap with a previous x
bin/stage2.sh ./build/stage1 <version>         # self-compile → build/stage2
bin/test.sh ./build/stage2                     # test suite (53 tests + std/fail sets)
bin/make_toolchain.sh ./build/stage2 <out> <version> [-zip]
```

Builds use a per-module object cache (`-cache`); editing a header-like
module invalidates its dependents automatically.

## Tools

- **Formatter** — `fmt <in.x> [out.x]` keeps comments and normalizes
  layout (see `src/formatter/main.x`):
  ```sh
  ./build/fmt_out/fmt hello.x hello_fmt.x   # build via bin/build_formatter.sh
  ```
- **LSP** — `src/lsp` (see `bin/build_lsp.sh`).
- **Debug info** — `x c -g …`; set `XBACKTRACE=1` for native backtraces
  on assertion failures.

## Repository layout

| Path              | Contents                                                     |
|-------------------|--------------------------------------------------------------|
| `src/ast`         | Lexer, parser, AST, pretty-printer (`fmt` backend)           |
| `src/resolver`    | Name/method/generics resolution, ownership, macros           |
| `src/backend`     | LLVM lowering (expression/statement emitters, FFI bridge)    |
| `src/parser`      | Compiler driver (`x c …`), incremental cache                 |
| `src/std`         | Standard library (`String`, collections, `fs`, `libc`, …)    |
| `src/formatter`   | `fmt` frontend                                               |
| `src/lsp`         | Language-server scaffolding                                  |
| `tests/normal`    | End-to-end tests (`// xfail:` / `// should-fail:` markers)   |
| `tests/std_test`  | Standard-library tests                                       |
| `tests/fail`      | Must-fail-to-compile tests                                   |
| `doc/`            | Language notes (`modules.txt`, `macros.txt`, …) and roadmap  |
| `cpp_bridge/`     | C++ side of the LLVM FFI                                     |

## Status

Pre-1.0 and moving fast: the suite is green on x86_64, cross toolchains
are published per release, and known gaps are tracked in `doc/todo`
(full macro support, release-mode stripping, `-O` pipeline wiring).
