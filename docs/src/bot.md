# SnoopCompile Bot

You can use SnoopCompile bot to automatically and continuously create precompile files.

One should add 3 things to a package to make the bot work:

----------------------------------


- workflow file:

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
        julia-version: ['nightly']
        julia-arch: [x64]
        os: [ubuntu-latest]
    steps:
      - uses: actions/checkout@v2
      - uses: julia-actions/setup-julia@latest
        with:
          version: ${{ matrix.julia-version }}
      - name: Install dependencies
        run: julia --project=@. -e 'using Pkg; Pkg.instantiate();'
      - name : Add SnoopCompile and current package
        run: julia -e 'using Pkg; Pkg.add(PackageSpec(url = "https://github.com/aminya/SnoopCompile.jl", rev ="packageSnooper")); Pkg.develop(PackageSpec(; path=pwd()));'
      - name: Install Test dependencies
        run: julia -e 'using SnoopCompile; SnoopCompile.addtestdep()'
      - name: Generating precompile files
        run: julia --project=@. -e 'include("deps/SnoopCompile/snoopCompile.jl")'

      # https://github.com/marketplace/actions/create-pull-request
      - name: Create Pull Request
        uses: peter-evans/create-pull-request@v2-beta
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          commit-message: Update precompile_*.jl file
          committer: Amin Yahyaabadi <aminyahyaabadi74@gmail.com>
          title: '[AUTO] Update precompile_*.jl file'
          labels: SnoopCompile
          branch: create-pull-request/SnoopCompile
      - name: Check output environment variable
        run: echo "Pull Request Number - ${{ env.PULL_REQUEST_NUMBER }}"
```
If your examples or tests have dependencies, you should add a `Test.toml` to your test folder.

`Install Test dependencies` step is only needed if you have test dependencies other than Test. Otherwise, you should comment it. For example for MatLang package:

[Link](https://github.com/juliamatlab/MatLang/blob/master/.github/workflows/SnoopCompile.yml)

Change `committer` to your name and your email.

----------------------------------


- Examples that call the package functions.

```julia
using SnoopCompile

@snoopiBot "MatLang" begin
  using MatLang
  examplePath = joinpath(dirname(dirname(pathof(MatLang))), "examples")
  include(joinpath(examplePath,"Language_Fundamentals", "usage_Entering_Commands.jl"))
  include(joinpath(examplePath,"Language_Fundamentals", "usage_Matrices_and_Arrays.jl"))
  include(joinpath(examplePath,"Language_Fundamentals", "Data_Types", "usage_Numeric_Types.jl"))
end
```
[Ref]( https://github.com/juliamatlab/MatLang/blob/master/deps/SnoopCompile/snoopCompile.jl)

If you do not have additional examples, you can use your runtests.jl file. To do that use:

```julia
using SnoopCompile

# using runtests:
@snoopiBot "Juno"
```
[Ref]( https://github.com/juliamatlab/MatLang/blob/master/deps/SnoopCompile/snoopCompile.jl)

----------------------------------

- Two lines of code that includes the precompile file

```julia
include("../deps/SnoopCompile/precompile/precompile_MatLang.jl")
_precompile_()
```

[Ref](https://github.com/juliamatlab/MatLang/blob/072ff8ed9877cbb34f8583ae2cf928a5df18aa0c/src/MatLang.jl#L26)


Or have it commented if you want to continuously develop your package offline, and only merge pull requests online:
```julia
# include("../deps/SnoopCompile/precompile/precompile_Juno.jl")
# _precompile_()
```
[Ref](https://github.com/aminya/Juno.jl/blob/1241d0f0ab421190ba9ff9a855666aef0cebfb55/src/Juno.jl#L32)
