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


 [`BotConfig`](@ref) is used to pass the settings to the bot. See [`BotConfig`](@ref) documentation to learn more. The below example shows an example of a `BotConfig` that supports multiple os, multiple version, and also has a function in its backlist.

This call should be like:

```julia
using SnoopCompile

botconfig = BotConfig(
  "Zygote";
  os = ["linux", "windows", "macos"],
  version = [v"1.4.1", v"1.3.1"],
  blacklist = ["SqEuclidean"],
  exhaustive = false,
)

snoopi_bot(
  botconfig,
  "$(@__DIR__)/example_script.jl",
)
```

[Zygote example](https://github.com/aminya/Zygote.jl/blob/SnoopCompile/deps/SnoopCompile/snoopi_bot.jl)

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

botconfig = BotConfig(
  "Zygote";
  os = ["linux", "windows", "macos"],
  version = [v"1.4.1", v"1.3.1"],
  blacklist = ["SqEuclidean"],
  exhaustive = false,
)

println("Benchmarking the inference time of example_script")
snoopi_bench(
  botconfig,
  "$(@__DIR__)/example_script.jl",
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

[Zygote example](https://github.com/aminya/Zygote.jl/blob/SnoopCompile/deps/SnoopCompile/snoopi_bench.jl)

## 4 - GitHub Action file (only for online run)

In your repository, create a workflow file under `.github/workflows/SnoopCompile.yml`, and use the following content:

```yaml
name: SnoopCompile


# Edit based on your repository.
on:
  push:
    branches:
      # - 'master'
  # pull_request:  # comment for big repositories

defaults:
  run:
    shell: bash

jobs:
  SnoopCompile:
    if: "!contains(github.event.head_commit.message, '[skip ci]')"
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        # Uncomment other versions if you want multi-version signatures (should exactly match BotConfig.version):
        version:
          - '1.4.1'
          - '1.3.1'
          # - '1.2.0' # min
        os:
          - ubuntu-latest
          - windows-latest
          - macos-latest
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
          julia -e 'using Pkg; Pkg.add(PackageSpec(url = "https://github.com/aminya/SnoopCompile.jl", rev = "multios")); Pkg.develop(PackageSpec(; path=pwd())); using SnoopCompile; SnoopCompile.addtestdep();'
      - name: Generating precompile files
        run: julia --project -e 'include("deps/SnoopCompile/snoopi_bot.jl")'
      - name: Running Benchmark
        run: julia --project -e 'include("deps/SnoopCompile/snoopi_bench.jl")'
      - name: Upload all
        uses: actions/upload-artifact@v2
        with:
          path: ./

  Create_PR:
    if: "!contains(github.event.head_commit.message, '[skip ci]')"
    needs: SnoopCompile
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Download all
        uses: actions/download-artifact@v2
      - name: Move the content of the directory to the root
        run: |
          rsync -a artifact/* ./
          rm -d -r artifact
      - name: Discard unrelated changes
        run: |
          test -f 'Project.toml' && git checkout -- 'Project.toml'
          git ls-files 'Manifest.toml' | grep . && git checkout -- 'Manifest.toml'
          (git diff -w --no-color || git apply --cached --ignore-whitespace && git checkout -- . && git reset && git add -p) || echo done
      - name: Format precompile_includer.jl
        run: julia -e 'using Pkg; Pkg.add("JuliaFormatter"); using JuliaFormatter; format_file("src/precompile_includer.jl")'
      - name: Create Pull Request
        # https://github.com/marketplace/actions/create-pull-request
        uses: peter-evans/create-pull-request@v2
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          commit-message: Update precompile_*.jl file
          # committer: YOUR NAME <yourEmail@something.com> # Change `committer` to your name and your email.
          title: "[AUTO] Update precompiles"
          labels: SnoopCompile
          branch: "SnoopCompile_AutoPR"


  Skip:
    if: "contains(github.event.head_commit.message, '[skip ci]')"
    runs-on: ubuntu-latest
    steps:
      - name: Skip CI 🚫
        run: echo skip ci
```

For example for Zygote package:

[Link](https://github.com/aminya/Zygote.jl/blob/SnoopCompile/.github/workflows/SnoopCompile.yml)
