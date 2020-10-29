function start_deep_timing()
    Core.Compiler.Timings.reset_timings()
    Core.Compiler.__set_measure_typeinf(true)
end
function stop_deep_timing()
    Core.Compiler.__set_measure_typeinf(false)
    Core.Compiler.Timings.close_current_timer()
end

function finish_snoopi_deep()
    return Core.Compiler.Timings._timings[1]
end

function _snoopi_deep(cmd::Expr)
    return quote
        start_deep_timing()
        try
            $(esc(cmd))
        finally
            stop_deep_timing()
        end
        finish_snoopi_deep()
    end
end

"""
    timing_tree = @snoopi_deep commands

Produce a profile of julia's type inference, containing the amount of time spent inferring
every `MethodInstance` processed while executing `commands`.

The top-level node in this profile tree is `ROOT`, which contains the time spent _not_ in
julia's type inference (codegen, llvm_opt, runtime, etc).

To make use of these results, see the processing functions in SnoopCompile:
    - [`SnoopCompile.flatten_times(timing_tree)`](@ref)
    - [`SnoopCompile.flamegraph(timing_tree)`](@ref)

# Examples
```julia
julia> timing = @snoopi_deep begin
           @eval sort(rand(100))  # Evaluate some code and profile julia's type inference
       end;

julia> using SnoopCompile, ProfileView

julia> times = flatten_times(timing, tmin_secs=0.001)
4-element Vector{Any}:
 0.001088448 => Core.Compiler.Timings.InferenceFrameInfo(MethodInstance for fpsort!(...
 0.001618478 => Core.Compiler.Timings.InferenceFrameInfo(MethodInstance for rand!(...
 0.002289655 => Core.Compiler.Timings.InferenceFrameInfo(MethodInstance for _rand_max383!(...
 0.093143594 => Core.Compiler.Timings.InferenceFrameInfo(MethodInstance for ROOT(), ...

julia> fg = flamegraph(timing)
Node(FlameGraphs.NodeData(ROOT() at typeinfer.jl:70, 0x00, 0:15355670))

julia> ProfileView.view(fg);  # Display the FlameGraph in a package that supports it

julia> fg = flamegraph(timing; tmin_secs=0.0001)  # Skip very tiny frames
Node(FlameGraphs.NodeData(ROOT() at typeinfer.jl:70, 0x00, 0:15355670))
```
"""
macro snoopi_deep(cmd)
    return _snoopi_deep(cmd)
end

# These are okay to come at the top-level because we're only measuring inference, and
# inference results will be cached in a `.ji` file.
@assert precompile(Core.Compiler.Timings.reset_timings, ())
@assert precompile(start_deep_timing, ())
@assert precompile(stop_deep_timing, ())
@assert precompile(finish_snoopi_deep, ())
