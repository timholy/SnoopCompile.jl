export @snoopi

const __inf_timing__ = Tuple{Float64,MethodInstance}[]
#const __inf_callees__ = Dict{MethodInstance, Vector{MethodInstance}}()
const __inf_callee_edges4__ = Dict{MethodInstance, Vector{Any}}()

if isdefined(Core.Compiler, :Params)
    function typeinf_ext_timed(linfo::Core.MethodInstance, params::Core.Compiler.Params)
        #Core.println("starting $linfo")
        #empty!(Core.Compiler.__inference_callees__)
        #empty!(Core.Compiler.__inference_callee_edges4__)
        push!(Core.Compiler.__inference_callee_edges4__, (linfo, Tuple{MethodInstance,MethodInstance}[]))
        tstart = time()
        ret = Core.Compiler.typeinf_ext(linfo, params)
        tstop = time()
        push!(__inf_timing__, (tstop-tstart, linfo))
        #__inf_callees__[linfo] = Core.Compiler.__inference_callees__
        @assert Core.Compiler.__inference_callee_edges4__[end][1] == linfo
        __inf_callee_edges4__[linfo] = pop!(Core.Compiler.__inference_callee_edges4__)[2]
        #Core.println("push: ", Core.Compiler.__inference_callee_edges4__)
        return ret
    end
    function typeinf_ext_timed(linfo::Core.MethodInstance, world::UInt)
        #Core.println("starting $linfo")
        #empty!(Core.Compiler.__inference_callees__)
        push!(Core.Compiler.__inference_callee_edges4__, (linfo, Tuple{MethodInstance,MethodInstance}[]))
        tstart = time()
        ret = Core.Compiler.typeinf_ext(linfo, world)
        tstop = time()
        push!(__inf_timing__, (tstop-tstart, linfo))
        #__inf_callees__[linfo] = Core.Compiler.__inference_callees__
        @assert Core.Compiler.__inference_callee_edges4__[end][1] == linfo
        __inf_callee_edges4__[linfo] = pop!(Core.Compiler.__inference_callee_edges4__)[2]
        #Core.println("push: ", Core.Compiler.__inference_callee_edges4__)
        return ret
    end
    @noinline function stop_timing()
        ccall(:jl_set_typeinf_func, Cvoid, (Any,), Core.Compiler.typeinf_ext)
        #ccall(:jl_set_typeinf_inner_func, Cvoid, (Any,), Core.Compiler.typeinf)
        Core.Compiler._set_typeinf_func(Core.Compiler._typeinf)
        #Core.Compiler.__collect_inference_callees__[] = false
    end
else
    function typeinf_ext_timed(interp::Core.Compiler.AbstractInterpreter, linfo::Core.MethodInstance)
        #Core.println("starting $linfo")
        #empty!(Core.Compiler.__inference_callees__)
        push!(Core.Compiler.__inference_callee_edges4__, (linfo, Tuple{MethodInstance,MethodInstance}[]))
        tstart = time()
        ret = Core.Compiler.typeinf_ext_toplevel(interp, linfo)
        tstop = time()
        push!(__inf_timing__, (tstop-tstart, linfo))
        #__inf_callees__[linfo] = Core.Compiler.__inference_callees__
        @assert Core.Compiler.__inference_callee_edges4__[end][1] == linfo
        __inf_callee_edges4__[linfo] = pop!(Core.Compiler.__inference_callee_edges4__)[2]
        #Core.println("push: ", Core.Compiler.__inference_callee_edges4__)
        return ret
    end
    function typeinf_ext_timed(linfo::Core.MethodInstance, world::UInt)
        #Core.println("starting $linfo")
        #empty!(Core.Compiler.__inference_callees__)
        push!(Core.Compiler.__inference_callee_edges4__, (linfo, Tuple{MethodInstance,MethodInstance}[]))
        tstart = time()
        ret = Core.Compiler.typeinf_ext_toplevel(linfo, world)
        tstop = time()
        push!(__inf_timing__, (tstop-tstart, linfo))
        #__inf_callees__[linfo] = Core.Compiler.__inference_callees__
        @assert Core.Compiler.__inference_callee_edges4__[end][1] == linfo
        __inf_callee_edges4__[linfo] = pop!(Core.Compiler.__inference_callee_edges4__)[2]
        #Core.println("push: ", Core.Compiler.__inference_callee_edges4__)
        return ret
    end
    @noinline function stop_timing()
        ccall(:jl_set_typeinf_func, Cvoid, (Any,), Core.Compiler.typeinf_ext_toplevel)
        #ccall(:jl_set_typeinf_inner_func, Cvoid, (Any,), Core.Compiler.typeinf)
        Core.Compiler._set_typeinf_func(Core.Compiler._typeinf)
        #Core.Compiler.__collect_inference_callees__[] = false
    end
end

@noinline function start_timing()
    ccall(:jl_set_typeinf_func, Cvoid, (Any,), typeinf_ext_timed2)
    #ccall(:jl_set_typeinf_inner_func, Cvoid, (Any,), typeinf_timed)
    Core.Compiler._set_typeinf_func(typeinf_timed)
    #Core.Compiler.__collect_inference_callees__[] = true
end

import TimerOutputs
const _to_ = TimerOutputs.TimerOutput()
function typeinf_timed(interp::Core.Compiler.AbstractInterpreter, frame::Core.Compiler.InferenceState)
    TimerOutputs.@timeit _to_ string(frame.linfo) begin
        Core.Compiler._typeinf(interp, frame)
    end
end
function typeinf_ext_timed2(interp::Core.Compiler.AbstractInterpreter, linfo::Core.MethodInstance)
    TimerOutputs.@timeit _to_ string(linfo) begin
        return Core.Compiler.typeinf_ext_toplevel(interp, linfo)
    end
end
function typeinf_ext_timed2(linfo::Core.MethodInstance, world::UInt)
    TimerOutputs.@timeit _to_ string(linfo) begin
        Core.Compiler.typeinf_ext_toplevel(linfo, world)
    end
end

function sort_timed_inf(tmin)
    data = __inf_timing__
    if tmin > 0.0
        data = filter(tl->tl[1] >= tmin, data)
    end
    data = sort(data; by=tl->tl[1])
    #@show __inf_callee_edges4__
    out = Tuple{Float64,MethodInstance,
                #Vector{MethodInstance},
                Vector{Pair{MethodInstance,MethodInstance}}}[
        (tl[1], tl[2],
            # Another (incorrect) view on all MethodInstances compiled during this inferable set
            #__inf_callees__[tl[2]],
            # The dependency graph of those compilations.
            [a=>b for (a,b) in __inf_callee_edges4__[tl[2]]]
        ) for (i,tl) in enumerate(data)
    ]
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
        #empty!(__inf_timing__)
        #empty!(__inf_callees__)
        #empty!(__inf_callee_edges4__)
        TimerOutputs.reset_timer!(_to_)
        start_timing()
        try
            $(esc(cmd))
        finally
            stop_timing()
        end
        #$sort_timed_inf($tmin)
        return deepcopy(_to_)
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
