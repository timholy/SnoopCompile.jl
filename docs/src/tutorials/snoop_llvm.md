# Tutorial on `@snoop_llvm`

Julia uses the [LLVM compiler](https://llvm.org/) to generate machine code. Typically, the two main contributors to the overall compile time are inference and LLVM, and thus together `@snoop_inference` and `@snoop_llvm` collect fairly comprehensive data on the compiler.

`@snoop_llvm` has a somewhat different design than `@snoop_inference`: while `@snoop_inference` runs in the same session that you'll be using for analysis (and thus requires that you remember to do the data gathering in a fresh session), `@snoop_llvm` spawns a fresh process to collect the data. The downside is that you get less interactivity, as the data have to be written out in intermediate forms as a text file.

### Add SnoopCompileCore and SnoopCompile to your environment

Here, we'll add these packages to your [default environment](https://pkgdocs.julialang.org/v1/environments/).

```
using Pkg
Pkg.add(["SnoopCompileCore", "SnoopCompile"]);
```

## Collecting the data

Here's a simple demonstration of usage:

```@repl tutorial-llvm
using SnoopCompileCore
@snoop_llvm "func_names.csv" "llvm_timings.yaml" begin
    using InteractiveUtils
    @eval InteractiveUtils.peakflops()
end

using SnoopCompile
times, info = SnoopCompile.read_snoop_llvm("func_names.csv", "llvm_timings.yaml", tmin_secs = 0.025);
```

This will write two files, `"func_names.csv"` and `"llvm_timings.yaml"`, in your current working directory. Let's look at what was read from these files:

```@repl tutorial-llvm
times
info
```

