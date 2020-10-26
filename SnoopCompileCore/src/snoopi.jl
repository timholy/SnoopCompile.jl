export @snoopi, @snoopi_deep

const __inf_timing__ = Tuple{Float64,MethodInstance}[]

if isdefined(Core.Compiler, :Params)
    function typeinf_ext_timed(linfo::Core.MethodInstance, params::Core.Compiler.Params)
        tstart = time()
        ret = Core.Compiler.typeinf_ext(linfo, params)
        tstop = time()
        push!(__inf_timing__, (tstop-tstart, linfo))
        return ret
    end
    function typeinf_ext_timed(linfo::Core.MethodInstance, world::UInt)
        tstart = time()
        ret = Core.Compiler.typeinf_ext(linfo, world)
        tstop = time()
        push!(__inf_timing__, (tstop-tstart, linfo))
        return ret
    end
    @noinline stop_timing() = ccall(:jl_set_typeinf_func, Cvoid, (Any,), Core.Compiler.typeinf_ext)
else
    function typeinf_ext_timed(interp::Core.Compiler.AbstractInterpreter, linfo::Core.MethodInstance)
        tstart = time()
        ret = Core.Compiler.typeinf_ext_toplevel(interp, linfo)
        tstop = time()
        push!(__inf_timing__, (tstop-tstart, linfo))
        return ret
    end
    function typeinf_ext_timed(linfo::Core.MethodInstance, world::UInt)
        tstart = time()
        ret = Core.Compiler.typeinf_ext_toplevel(linfo, world)
        tstop = time()
        push!(__inf_timing__, (tstop-tstart, linfo))
        return ret
    end
    @noinline stop_timing() = ccall(:jl_set_typeinf_func, Cvoid, (Any,), Core.Compiler.typeinf_ext_toplevel)
end

@noinline start_timing() = ccall(:jl_set_typeinf_func, Cvoid, (Any,), typeinf_ext_timed)

function sort_timed_inf(tmin)
    data = __inf_timing__
    if tmin > 0.0
        data = filter(tl->tl[1] >= tmin, data)
    end
    return sort(data; by=tl->tl[1])
end

"""
    inf_timing = @snoopi commands
    inf_timing = @snoopi tmin=0.0 commands

Execute `commands` while snooping on inference. Returns an array of `(t, linfo)`
tuples, where `t` is the amount of time spent inferring `linfo` (a `MethodInstance`).

Methods that take less time than `tmin` will not be reported.
"""
macro snoopi(args...)
    tmin = 0.0
    if length(args) == 1
        cmd = args[1]
    elseif length(args) == 2
        a = args[1]
        if isa(a, Expr) && a.head == :(=) && a.args[1] == :tmin
            tmin = a.args[2]
            cmd = args[2]
        else
            error("unrecognized input ", a)
        end
    else
        error("at most two arguments are supported")
    end
    return _snoopi(cmd, tmin)
end

function _snoopi(cmd::Expr, tmin = 0.0)
    return quote
        empty!(__inf_timing__)
        start_timing()
        try
            $(esc(cmd))
        finally
            stop_timing()
        end
        $sort_timed_inf($tmin)
    end
end

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
    - [`SnoopCompile.to_flamegraph(timing_tree)`](@ref)

# Examples
```julia
julia> timing = SnoopCompileCore.@snoopi_deep begin
           @eval sort(rand(100))  # Evaluate some code and profile julia's type inference
       end;

julia> using SnoopCompile, ProfileView

julia> times = SnoopCompile.flatten_times(timing, tmin_secs=0.001)
4-element Vector{Any}:
 0.001088448 => Core.Compiler.Timings.InferenceFrameInfo(MethodInstance for fpsort!(...
 0.001618478 => Core.Compiler.Timings.InferenceFrameInfo(MethodInstance for rand!(...
 0.002289655 => Core.Compiler.Timings.InferenceFrameInfo(MethodInstance for _rand_max383!(...
 0.093143594 => Core.Compiler.Timings.InferenceFrameInfo(MethodInstance for ROOT(), ...

julia> fg = SnoopCompile.to_flamegraph(timing)
Node(FlameGraphs.NodeData(ROOT() at typeinfer.jl:70, 0x00, 0:15355670))

julia> ProfileView.view(fg);  # Display the FlameGraph in a package that supports it

julia> fg = SnoopCompile.to_flamegraph(timing; tmin_secs=0.0001)  # Skip very tiny frames
Node(FlameGraphs.NodeData(ROOT() at typeinfer.jl:70, 0x00, 0:15355670))
```

"""
macro snoopi_deep(cmd)
    return _snoopi_deep(cmd)
end


function __init__()
    # typeinf_ext_timed must be compiled before it gets run
    # We do this in __init__ to make sure it gets compiled to native code
    # (the *.ji file stores only the inferred code)
    if isdefined(Core.Compiler, :Params)
        @assert precompile(typeinf_ext_timed, (Core.MethodInstance, Core.Compiler.Params))
        @assert precompile(typeinf_ext_timed, (Core.MethodInstance, UInt))
    else
        @assert precompile(typeinf_ext_timed, (Core.Compiler.NativeInterpreter, Core.MethodInstance))
        @assert precompile(typeinf_ext_timed, (Core.MethodInstance, UInt))
    end
    precompile(start_timing, ())
    precompile(stop_timing, ())

    @assert precompile(Core.Compiler.Timings.reset_timings, ())
    @assert precompile(start_deep_timing, ())
    @assert precompile(stop_deep_timing, ())
    @assert precompile(finish_snoopi_deep, ())

    nothing
end
