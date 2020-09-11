export @snoopi

const __inf_timing__ = Tuple{Float64,MethodInstance}[]
const __inf_callees__ = Dict{MethodInstance, Vector{MethodInstance}}()

if isdefined(Core.Compiler, :Params)
    function typeinf_ext_timed(linfo::Core.MethodInstance, params::Core.Compiler.Params)
        empty!(Core.Compiler.__inference_callees__)
        tstart = time()
        ret = Core.Compiler.typeinf_ext(linfo, params)
        tstop = time()
        push!(__inf_timing__, (tstop-tstart, linfo))
        __inf_callees__[linfo] = Core.Compiler.__inference_callees__
        return ret
    end
    function typeinf_ext_timed(linfo::Core.MethodInstance, world::UInt)
        empty!(Core.Compiler.__inference_callees__)
        tstart = time()
        ret = Core.Compiler.typeinf_ext(linfo, world)
        tstop = time()
        push!(__inf_timing__, (tstop-tstart, linfo))
        __inf_callees__[linfo] = Core.Compiler.__inference_callees__
        return ret
    end
    @noinline function stop_timing()
        ccall(:jl_set_typeinf_func, Cvoid, (Any,), Core.Compiler.typeinf_ext)
        Core.Compiler.__collect_inference_callees__[] = false
    end
else
    function typeinf_ext_timed(interp::Core.Compiler.AbstractInterpreter, linfo::Core.MethodInstance)
        empty!(Core.Compiler.__inference_callees__)
        tstart = time()
        ret = Core.Compiler.typeinf_ext_toplevel(interp, linfo)
        tstop = time()
        push!(__inf_timing__, (tstop-tstart, linfo))
        __inf_callees__[linfo] = Core.Compiler.__inference_callees__
        return ret
    end
    function typeinf_ext_timed(linfo::Core.MethodInstance, world::UInt)
        empty!(Core.Compiler.__inference_callees__)
        tstart = time()
        ret = Core.Compiler.typeinf_ext_toplevel(linfo, world)
        tstop = time()
        push!(__inf_timing__, (tstop-tstart, linfo))
        __inf_callees__[linfo] = Core.Compiler.__inference_callees__
        return ret
    end
    @noinline function stop_timing()
        ccall(:jl_set_typeinf_func, Cvoid, (Any,), Core.Compiler.typeinf_ext_toplevel)
        Core.Compiler.__collect_inference_callees__[] = false
    end
end

@noinline function start_timing()
    ccall(:jl_set_typeinf_func, Cvoid, (Any,), typeinf_ext_timed)
    Core.Compiler.__collect_inference_callees__[] = true
end

function sort_timed_inf(tmin)
    data = __inf_timing__
    if tmin > 0.0
        data = filter(tl->tl[1] >= tmin, data)
    end
    data = sort(data; by=tl->tl[1])
    out = Tuple{Float64,Vector{MethodInstance}}[(tl[1], __inf_callees__[tl[2]]) for tl in data]
    return out
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
        empty!(__inf_callees__)
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
