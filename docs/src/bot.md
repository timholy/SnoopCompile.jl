# SnoopCompile Bot (EXPERIMENTAL)

You can use SnoopCompile bot to automatically and continuously create precompile files.

One should add 3 things to a package to make the bot work:

----------------------------------


- Workflow file:

create a workflow file with this path in your repository `.github/workflows/SnoopCompile.yml` and use the following content:

```yaml
name: SnoopCompile

on:
  - push


jobs:
  build:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        julia-version: ['1.4.0-rc1'] # using 1.4 and higher is better
        julia-arch: [x64]
        os: [ubuntu-latest]
    steps:
      - uses: actions/checkout@v2
      - uses: julia-actions/setup-julia@latest
        with:
          version: ${{ matrix.julia-version }}
      - name: Install dependencies
        run: julia --project -e 'using Pkg; Pkg.instantiate();'
      - name : Add SnoopCompile and current package
        run: julia -e 'using Pkg; Pkg.add("SnoopCompile"); Pkg.develop(PackageSpec(; path=pwd()));'
      - name: Install Test dependencies
        run: julia -e 'using SnoopCompile; SnoopCompile.addtestdep()'
      - name: Generating precompile files
        run: julia --project=@. -e 'include("deps/SnoopCompile/snoopCompile.jl")'
      - name: Running Benchmark
        run: julia --project=@. -e 'include("deps/SnoopCompile/snoopBenchmark.jl")'

      # https://github.com/marketplace/actions/create-pull-request
      - name: Create Pull Request
        uses: peter-evans/create-pull-request@v2
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          commit-message: Update precompile_*.jl file
          committer: YOUR NAME <yourEmail@something.com> # Change `committer` to your name and your email.
          title: '[AUTO] Update precompile_*.jl file'
          labels: SnoopCompile
          branch: create-pull-request/SnoopCompile
      - name: Check output environment variable
        run: echo "Pull Request Number - ${{ env.PULL_REQUEST_NUMBER }}"
```
`Install Test dependencies` step is only needed if you have test dependencies other than Test. Otherwise, you should comment it. In this case, if your examples or tests have dependencies, you should add a `Test.toml` to your test folder.

```yaml
- name: Install Test dependencies
  run: julia -e 'using SnoopCompile; SnoopCompile.addtestdep()'
```

For example for MatLang package:

[Link](https://github.com/juliamatlab/MatLang/blob/master/.github/workflows/SnoopCompile.yml)

----------------------------------


- Precompile script

Add a `snoopCompile.jl` file under `deps/SnoopCompile`. The content of the file should be a script that "exercises" the functionality you'd like to precompile. One option is to use your package's `"runtests.jl"` file, or you can write a custom script for this purpose.


For example, some examples that call the functions:

```julia
using SnoopCompile

@snoopi_bot "MatLang" begin
  using MatLang
  examplePath = joinpath(dirname(dirname(pathof(MatLang))), "examples")
  include(joinpath(examplePath,"Language_Fundamentals", "usage_Entering_Commands.jl"))
  include(joinpath(examplePath,"Language_Fundamentals", "usage_Matrices_and_Arrays.jl"))
  include(joinpath(examplePath,"Language_Fundamentals", "Data_Types", "usage_Numeric_Types.jl"))
end
```
[Ref]( https://github.com/juliamatlab/MatLang/blob/master/deps/SnoopCompile/snoopCompile.jl)

or if you do not have additional examples, you can use your runtests.jl file using this syntax:

```julia
using SnoopCompile

# using runtests:
@snoopi_bot "MatLang"
```

[Also look at this](https://timholy.github.io/SnoopCompile.jl/stable/snoopi/#Precompile-scripts-1)

----------------------------------

- Include precompile signatures

Two lines of (commented) code that includes the precompile file in your main module.

It is better to have these lines commented to continuously develop and change your package offline. snoopi_bot will find these lines of code and will uncomment them in the created pull request. If they are not commented the bot will leave it as is in the pull request:

```julia
# include("../deps/SnoopCompile/precompile/precompile_MatLang.jl")
# _precompile_()
```

[Ref](https://github.com/juliamatlab/MatLang/blob/072ff8ed9877cbb34f8583ae2cf928a5df18aa0c/src/MatLang.jl#L26)


----------------------------------


## Benchmark

To measure the effect of adding precompile files. Add a `snoopBenchmark.jl`. The content of this file can be the following:

Benchmarking the load infer time
```julia
using SnoopCompile
println("loading infer benchmark")

@snoopi_bench "MatLang" using MatLang
```

Benchmarking the example infer time
```julia
using SnoopCompile
println("examples infer benchmark")

@snoopi_bench "MatLang" begin
    using MatLang
    examplePath = joinpath(dirname(dirname(pathof(MatLang))), "examples")
    # include(joinpath(examplePath,"Language_Fundamentals", "usage_Entering_Commands.jl"))
    include(joinpath(examplePath,"Language_Fundamentals", "usage_Matrices_and_Arrays.jl"))
    include(joinpath(examplePath,"Language_Fundamentals", "Data_Types", "usage_Numeric_Types.jl"))
end
```

Benchmarking the tests:
```julia
using SnoopCompile
@snoopi_bench "MatLang"
```
[Ref](https://github.com/juliamatlab/MatLang/blob/master/deps/SnoopCompile/snoopBenchmark.jl)


To run the benchmark online, add the following to your yaml file after `Generating precompile files` step:

```yaml
- name: Running Benchmark
  run: julia --project=@. -e 'include("deps/SnoopCompile/snoopBenchmark.jl")'
```
