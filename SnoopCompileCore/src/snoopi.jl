export @snoopi

const __inf_timing__ = Tuple{Float64,MethodInstance}[]
const __inner_timings__ = Ref{Vector{Any}}()

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
    @noinline stop_timing() = begin
        #ccall(:jl_set_typeinf_func, Cvoid, (Any,), Core.Compiler.typeinf_ext)
        Core.Compiler.__toggle_measure_typeinf(false)
    end
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
    @noinline stop_timing() = begin
        #ccall(:jl_set_typeinf_func, Cvoid, (Any,), Core.Compiler.typeinf_ext_toplevel)
        Core.Compiler.__toggle_measure_typeinf(false)
    end
end

@noinline start_timing() = begin
    #ccall(:jl_set_typeinf_func, Cvoid, (Any,), typeinf_ext_timed)
    Core.Compiler.__toggle_measure_typeinf(true)
end

function sort_timed_inf(tmin)
    return copy(Core.Compiler.Timings._timings)

    data = __inf_timing__
    if tmin > 0.0
        data = filter(tl->tl[1] >= tmin, data)
    end
    return sort(data; by=tl->tl[1])
end

function flatten_times(timings::Vector, tmin_secs = 0.0)
    tmin_ns = tmin_secs * 1e9
    out = Any[]
    frontier = copy(timings)
    i = 1
    while !isempty(frontier)
        t = popfirst!(frontier)
        if i != 1 && t.time < tmin_ns
            continue
        end
        if i !== 1  # Skip "root" node
            exclusive_time = (t.time / 1e9)
            if exclusive_time >= tmin_secs
                push!(out, exclusive_time => t.name)
            end
        end
        i += 1
        for c in t.children
            push!(frontier, c)
        end
    end
    return sort(out; by=tl->tl[1])
end

"""
    inf_timing = @snoopi commands
    inf_timing = @snoopi tmin=0.0 commands

Execute `commands` while snooping on inference. Returns an array of `(t, linfo)`
tuples, where `t` is the amount of time spent infering `linfo` (a `MethodInstance`).

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
        Core.Compiler.Timings.reset_timings()
        start_timing()
        try
            $(esc(cmd))
        finally
            stop_timing()
        end
        $sort_timed_inf($tmin)
    end
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
    nothing
end
