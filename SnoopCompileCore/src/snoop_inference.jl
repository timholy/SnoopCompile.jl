export @snoop_inference

const snoop_inference_lock = ReentrantLock()
const newly_inferred = Core.CodeInstance[]

function start_tracking()
    islocked(snoop_inference_lock) && error("already tracking inference (cannot nest `@snoop_inference` blocks)")
    lock(snoop_inference_lock)
    empty!(newly_inferred)
    ccall(:jl_set_newly_inferred, Cvoid, (Any,), newly_inferred)
    return nothing
end

function stop_tracking()
    @assert islocked(snoop_inference_lock)
    ccall(:jl_set_newly_inferred, Cvoid, (Any,), nothing)
    unlock(snoop_inference_lock)
    return nothing
end

"""
    tinf = @snoop_inference commands;

Produce a profile of julia's type inference, recording the amount of time spent
inferring every `MethodInstance` processed while executing `commands`. Each
fresh entrance to type inference (whether executed directly in `commands` or
because a call was made by runtime-dispatch) also collects a backtrace so the
caller can be identified.

`tinf` is a tree, each node containing data on a particular inference "frame"
(the method, argument-type specializations, parameters, and even any
constant-propagated values). Each reports the
[`exclusive`](@ref)/[`inclusive`](@ref) times, where the exclusive time
corresponds to the time spent inferring this frame in and of itself, whereas the
inclusive time includes the time needed to infer all the callees of this frame.

The top-level node in this profile tree is `ROOT`. Uniquely, its exclusive time
corresponds to the time spent _not_ in julia's type inference (codegen,
llvm_opt, runtime, etc).

Working with `tinf` effectively requires loading `SnoopCompile`.

!!! warning
    Note the semicolon `;` at the end of the `@snoop_inference` macro call.
    Because `SnoopCompileCore` is not permitted to invalidate any code, it cannot define
    the `Base.show` methods that pretty-print `tinf`. Defer inspection of `tinf`
    until `SnoopCompile` has been loaded.

# Example

```jldoctest; setup=:(using SnoopCompileCore), filter=r"([0-9]*\\.?[0-9]+([eE][-+]?[0-9]+)?/[0-9]*\\.?[0-9]+([eE][-+]?[0-9]+)?|\\d direct)"
julia> tinf = @snoop_inference begin
           sort(rand(100))  # Evaluate some code and profile julia's type inference
       end;
```
"""
macro snoop_inference(cmd)
    return esc(quote
        $(SnoopCompileCore.start_tracking)()
        try
            $cmd
        finally
            $(SnoopCompileCore.stop_tracking)()
        end
        ($(Base.copy))($(SnoopCompileCore.newly_inferred))
    end)
end

precompile(start_tracking, ())
precompile(stop_tracking, ())
