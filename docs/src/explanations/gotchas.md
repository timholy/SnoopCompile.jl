# Precompilation "gotcha"s

## [Running code during module definition](@ref running-during-pc)

Suppose you're working on an astronomy package and your source code has a line

```
const planets = map(makeplanet, ["Mercury", ...])
```

Julia will dutifully create `planets` and store it in the package's precompile cache file. This also runs `makeplanet`, and if this is the first time it gets run, it will compile `makeplanet`. Assuming that `makeplanet` is a method defined in the package, the compiled code for `makeplanet` will be stored in the cache file.

However, two circumstances can lead to puzzling omissions from the cache files:
- if `makeplanet` is a method defined in a dependency of your package, it will *not* be cached in your package. You'd want to add precompilation of `makeplanet` to the package that creates that method.
- if `makeplanet` is poorly-infered and uses runtime dispatch, any such callees that are not owned by your package will not be cached. For example, suppose `makeplanet` ends up calling methods in Base Julia or its standard libraries that are not precompiled into Julia itself: the compiled code for those methods will not be added to the cache file.

One option to ensure this dependent code gets cached is to create `planets` inside `@compile_workload`:

```
@compile_workload begin
    global planets
    const planet = map(makeplanet, ["Mercury", ...])
end
```

Note that your package definition can have multiple `@compile_workload` blocks.
