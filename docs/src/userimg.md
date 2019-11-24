# [Creating `userimg.jl` files](@id userimg)

If you want to save more precompile information, one option is to create a `"userimg.jl`"
file with with to build Julia.
This is only supported for `@snoopc`.
Instead of calling `SnoopCompile.parcel` and `SnoopCompile.write`, use the following:

```julia
# Use these two lines if you want to add to your userimg.jl
pc = SnoopCompile.format_userimg(reverse!(data[2]))
SnoopCompile.write("/tmp/userimg_Images.jl", pc)
```

Now move the resulting file to your Julia source directory, and create a `userimg.jl`
file that `include`s all the package-specific precompile files you want.
Then build Julia from source.
You should note that your latencies decrease substantially.

**There are serious negatives associated with a `userimg.jl` script**:
- Your julia build times become very long
- `Pkg.update()` will have no effect on packages that you've built into julia until you next recompile julia itself. Consequently, you may not get the benefit of enhancements or bug fixes.
- For a package that you sometimes develop, this strategy is very inefficient, because testing a change means rebuilding Julia as well as your package.

A process similar to this one is also performed via
[PackageCompiler](https://github.com/JuliaLang/PackageCompiler.jl).
