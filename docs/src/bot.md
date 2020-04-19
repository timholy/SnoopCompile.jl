# SnoopCompile Bot (EXPERIMENTAL)

You can use SnoopCompile bot to automatically and continuously create precompile files.

One should add 3 things to a package to make the bot work:

----------------------------------


- Workflow file:

create a workflow file with this path in your repository `.github/workflows/SnoopCompile.yml` and use the following content:

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
          # - '1.2.0'
          # - '1.0.5'
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
          version: ${{ matrix.julia-version }}
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

----------------------------------

# Precompile script

Add a `snoopi_bot.jl` file under `deps/SnoopCompile`. The content of the file should be a script that "exercises" the functionality you'd like to precompile. One option is to use your package's `"runtests.jl"` file, or you can write a custom script for this purpose.

[`BotConfig`](@ref) can be used to passing extra settings to the bot. See [`BotConfig`](@ref) documentation to learn more. The following example shows an example of a BotConfig that supports multiple os, multiple version, and also has a function in its backlist.

```julia
@snoopi_bot BotConfig("MatLang", blacklist = ["badfunction"], os = ["linux", "windows", "macos"], else_os = nothing, version = ["1.4.1", "1.2", "1.0.5"], else_version = "1.4.1" )
```

An example with custom script that call the functions:

```julia
using SnoopCompile

@snoopi_bot BotConfig("MatLang") begin
  using MatLang
  examplePath = joinpath(dirname(dirname(pathof(MatLang))), "examples")
  include(joinpath(examplePath,"Language_Fundamentals", "usage_Entering_Commands.jl"))
  include(joinpath(examplePath,"Language_Fundamentals", "usage_Matrices_and_Arrays.jl"))
  include(joinpath(examplePath,"Language_Fundamentals", "Data_Types", "usage_Numeric_Types.jl"))
end
```
[Ref]( https://github.com/juliamatlab/MatLang/blob/master/deps/SnoopCompile/snoopi_bot.jl)

or if you do not have additional examples, you can use your runtests.jl file using this syntax:

```julia
using SnoopCompile

# using runtests:
@snoopi_bot BotConfig("MatLang")
```

[Also look at this](https://timholy.github.io/SnoopCompile.jl/stable/snoopi/#Precompile-scripts-1)
----------------------------------

## Benchmark

To measure the effect of adding precompile files. Add a `snoopi_bench.jl`. The content of this file can be the following:

Benchmarking the load infer time
```julia
println("loading infer benchmark")

@snoopi_bench BotConfig("MatLang") using MatLang
```

Benchmarking the example infer time
```julia
println("examples infer benchmark")

@snoopi_bench BotConfig("MatLang") begin
    using MatLang
    examplePath = joinpath(dirname(dirname(pathof(MatLang))), "examples")
    # include(joinpath(examplePath,"Language_Fundamentals", "usage_Entering_Commands.jl"))
    include(joinpath(examplePath,"Language_Fundamentals", "usage_Matrices_and_Arrays.jl"))
    include(joinpath(examplePath,"Language_Fundamentals", "Data_Types", "usage_Numeric_Types.jl"))
end
```

Benchmarking the tests:
```julia
@snoopi_bench BotConfig("MatLang")
```
[Ref](https://github.com/juliamatlab/MatLang/blob/master/deps/SnoopCompile/snoopi_bench.jl)


To run the benchmark online, add the following to your yaml file after `Generating precompile files` step:

```yaml
- name: Running Benchmark
  run: julia --project=@. -e 'include("deps/SnoopCompile/snoopi_bench.jl")'
```
