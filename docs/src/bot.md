# SnoopCompile Bot

You can use SnoopCompile bot to automatically and continuously create precompile files. This bot can be used offline or online.

Follow these steps to setup SnoopCompile bot:

## 1 - Example/Test script

You should have `example_script.jl` that "exercises" the functionality you'd like to precompile.

**Recommendation**: add `example_script.jl` under `deps/SnoopCompile` (or at the same path that is referenced in the calls in section 2 and 3).

One option is to use your package's `"runtests.jl"` file. In this case, a simpler syntax is offered. See section 2 and 3.

## 2 - Call `snoopi_bot` function

Call the `snoopi_bot` function to generate precompile signatures.

**Recommendation**:
 - add a `snoopi_bot.jl` under `deps/SnoopCompile` (or at the same path that is referenced in yaml file).
 - or call the function directly from the yaml file.

This call should be like:

```julia
using SnoopCompile

snoopi_bot(
  BotConfig("MatLang"; blacklist = ["badfun"], os = ["linux", "windows", "macos"], else_os = "linux", version = [v"1.4.1", v"1.2"]),
  "\$(@__DIR__)/example_script.jl",
)
```

[`BotConfig`](@ref) can be used to passing extra settings to the bot. See [`BotConfig`](@ref) documentation to learn more. The above example shows an example of a `BotConfig` that supports multiple os, multiple version, and also has a function in its backlist.

[Ref]( https://github.com/juliamatlab/MatLang/blob/master/deps/SnoopCompile/snoopi_bot.jl)

If you do not have additional examples, you can use your runtests.jl file using this syntax:

```julia
using SnoopCompile

# using runtests:
snoopi_bot( BotConfig("MatLang") )
```

[Also look at this](https://timholy.github.io/SnoopCompile.jl/stable/snoopi/#Precompile-scripts-1)
----------------------------------

## 3 - Call `snoopi_bench` function

Call the `snoopi_bench` function to measure the effect of adding precompile files,

**Recommendation**:
 - add a `snoopi_bench.jl` under `deps/SnoopCompile` (or at the same path that is referenced in yaml file).
 - or call the function directly from the yaml file.

Benchmarking the inference time of example_script
```julia

using SnoopCompile

println("Benchmarking the inference time of example_script")
snoopi_bench(
  BotConfig("MatLang"; blacklist = ["badfun"], os = ["linux", "windows", "macos"], else_os = "linux", version = [v"1.4.1", v"1.2"]),
  "\$(@__DIR__)/example_script.jl",
)
```

Benchmarking the inference time of the tests
```julia
println("Benchmarking the inference time of the tests")
snoopi_bench(BotConfig("MatLang"))
```

To selectively exclude some of your tests from running by SnoopCompile bot, use the global SnoopCompile_ENV::Bool variable.
```julia
if !isdefined(Main, :SnoopCompile_ENV) || SnoopCompile_ENV == false
  # the tests you want to skip in SnoopCompile environment
end
```

Benchmarking inference time of loading
```julia
println("Benchmarking inference time of loading")
snoopi_bench( BotConfig("MatLang"), :(using MatLang) ) # this syntax should be avoided for complex expressions
```

[Ref](https://github.com/juliamatlab/MatLang/blob/master/deps/SnoopCompile/snoopi_bench.jl)

## 4 - GitHub Action file (only for online run)

In your repository, create a workflow file under `.github/workflows/SnoopCompile.yml`, and use the following content:

```yaml
name: SnoopCompile

# Only runs on pushes. Edit based on your taste.
on:
  push:
    branches:
      # - 'master'
  # pull_request:

defaults:
  run:
    shell: bash

jobs:
  SnoopCompile:
    if: "!contains(github.event.head_commit.message, '[skip ci]')"
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        # Uncomment other versions if you want multi-version signatures (should exactly match BotConfig.version):
        version:
          - '1.4.1'
          # - '1.2.0' # min
        # Uncomment other options if you want multi-os signatures (currently only these are supported by Github):
        os:
          - ubuntu-latest
          # - windows-latest
          # - macos-latest
        arch:
          - x64
    steps:
      - uses: actions/checkout@v2
      - uses: julia-actions/setup-julia@latest
        with:
          version: ${{ matrix.version }}
      - name: Install dependencies
        run: |
          julia --project -e 'using Pkg; Pkg.instantiate();'
          julia -e 'using Pkg; Pkg.add(PackageSpec(url = "https://github.com/aminya/SnoopCompile.jl", rev = "multios")); Pkg.develop(PackageSpec(; path=pwd())); Pkg.add("JuliaFormatter"); using SnoopCompile; SnoopCompile.addtestdep();'
      - name: Generating precompile files
        run: julia --project -e 'include("deps/SnoopCompile/snoopi_bot.jl")'
      - name: Running Benchmark
        run: julia --project -e 'include("deps/SnoopCompile/snoopi_bench.jl")'
      - name: Format precompile_includer.jl
        run: julia --project -e 'using JuliaFormatter; format_file("src/precompile_includer.jl")'
      - name: Upload all
        uses: actions/upload-artifact@v2-preview
        with:
          path: ./

  Create_PR:
    if: "!contains(github.event.head_commit.message, '[skip ci]')"
    needs: SnoopCompile
    runs-on: ubuntu-latest
    steps:
      - name: Download all
        uses: actions/download-artifact@v2-preview
      - name: Move the content of the directory to the root
        run: |
          mv -v artifact/* ./
          mv -v artifact/.[^.]* ./
      - name: Discard unrelated changes
        run: |
          git checkout -- Project.toml
          git diff -w --no-color | git apply --cached --ignore-whitespace && git checkout -- . && git reset && git add -p
      - name: Create Pull Request
        # https://github.com/marketplace/actions/create-pull-request
        uses: peter-evans/create-pull-request@v2
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          commit-message: Update precompile_*.jl file
          # committer: YOUR NAME <yourEmail@something.com> # Change `committer` to your name and your email.
          title: "[AUTO] Update precompiles'"
          labels: SnoopCompile
          branch: "SnoopCompile"


  Skip:
    if: "contains(github.event.head_commit.message, '[skip ci]')"
    runs-on: ubuntu-latest
    steps:
      - name: Skip CI 🚫
        run: echo skip ci
```

For example for MatLang package:

[Link](https://github.com/juliamatlab/MatLang/blob/master/.github/workflows/SnoopCompile.yml)
